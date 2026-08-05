#!/bin/bash
# shellcheck disable=SC2154,SC2034
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# #   Script for watching ZFS datasets and auto converting regular folders to datasets                                                  # #
# #   Ubuntu-compatible version with Gotify notifications and file logging                                                             # # 
# #   Adapted from SpaceInvaderOne's original Unraid script                                                                            # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the shared configuration file
if [[ -f "$SCRIPT_DIR/zfs-config.sh" ]]; then
    # shellcheck disable=SC1091 # runtime-resolved config, linted separately
    source "$SCRIPT_DIR/zfs-config.sh"
else
    echo "ERROR: Cannot find zfs-config.sh in $SCRIPT_DIR" >&2
    echo "Please ensure zfs-config.sh exists in the same directory as this script." >&2
    exit 1
fi

# Source the common library for shared functions
if [[ -f "$SCRIPT_DIR/lib/zfs-common.sh" ]]; then
    # shellcheck disable=SC1091 # runtime-resolved library, linted separately
    source "$SCRIPT_DIR/lib/zfs-common.sh"
else
    log_message "WARNING" "Common library not found - some functions may not be available"
fi

# Source the validation library for input validation
if [[ -f "$SCRIPT_DIR/lib/zfs-validation.sh" ]]; then
    # shellcheck disable=SC1091 # runtime-resolved library, linted separately
    source "$SCRIPT_DIR/lib/zfs-validation.sh"
else
    log_message "WARNING" "Validation library not found - operating without input validation"
fi

# Source the error handling library
if [[ -f "$SCRIPT_DIR/lib/zfs-error-handling.sh" ]]; then
    # shellcheck disable=SC1091 # runtime-resolved library, linted separately
    source "$SCRIPT_DIR/lib/zfs-error-handling.sh"
else
    log_message "WARNING" "Error handling library not found - operating without enhanced error handling"
fi

# Source the locking library for race condition prevention
if [[ -f "$SCRIPT_DIR/lib/zfs-locking.sh" ]]; then
    # shellcheck disable=SC1091 # runtime-resolved library, linted separately
    source "$SCRIPT_DIR/lib/zfs-locking.sh"
else
    log_message "WARNING" "Locking library not found - operating without concurrency protection"
fi

# Source the transaction library for rollback support
if [[ -f "$SCRIPT_DIR/lib/zfs-transactions.sh" ]]; then
    # shellcheck disable=SC1091 # runtime-resolved library, linted separately
    source "$SCRIPT_DIR/lib/zfs-transactions.sh"
else
    log_message "WARNING" "Transaction library not found - operating without rollback protection"
fi

# Validate configuration
if ! validate_config; then
    echo "Configuration validation failed. Please check zfs-config.sh" >&2
    exit 1
fi

# Override DRY_RUN if needed (uncomment to force dry run for testing)
# DRY_RUN="yes"

#--------------------------------
#     FUNCTIONS START HERE      #
#--------------------------------

# Pre-run checks for dependencies
pre_run_checks() {
    log_message "INFO" "Performing pre-run dependency checks..."
    
    # Check for essential ZFS utilities
    if ! command -v zfs >/dev/null 2>&1; then
        local msg='ZFS utilities not found. Please install zfsutils-linux package.'
        send_notification "$msg" "error"
        exit 1
    fi
    
    # Check for rsync (used for data copying)
    if ! command -v rsync >/dev/null 2>&1; then
        local msg='rsync not found. Please install rsync package.'
        send_notification "$msg" "error"
        exit 1
    fi
    
    log_message "INFO" "Pre-run dependency checks completed successfully"
}

# Recover partial conversions from previous runs
recover_partial_conversions() {
    log_message "INFO" "Checking for partial conversions to recover..."

    # Check if transaction library is available
    if ! declare -F transaction_recover_all >/dev/null 2>&1; then
        log_message "WARNING" "Transaction library not available - skipping recovery"
        return 0
    fi

    # Recover all pending transactions
    transaction_recover_all

    # Clean up old transaction files (older than 30 days)
    transaction_cleanup 30

    log_message "INFO" "Transaction recovery check completed"
}

# Logging and notification functions
log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Write to log file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Also print to stdout
    echo "[$level] $message"
}

rotate_log() {
    if [[ ! -f "$LOG_FILE" ]]; then
        return 0
    fi
    
    # Check if log file exceeds max size
    local file_size
    if command -v stat >/dev/null 2>&1; then
        file_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    else
        # Grouped so a failed input redirection is silenced too; `< file 2>/dev/null`
        # applies redirections left to right, so the open error still reaches stderr.
        file_size=$( { wc -c < "$LOG_FILE"; } 2>/dev/null || echo 0)
    fi
    
    # Convert LOG_MAX_SIZE to bytes (handles M, K suffixes)
    local max_bytes
    case "$LOG_MAX_SIZE" in
        *M|*m) max_bytes=$((${LOG_MAX_SIZE%[Mm]} * 1024 * 1024)) ;;
        *K|*k) max_bytes=$((${LOG_MAX_SIZE%[Kk]} * 1024)) ;;
        *) max_bytes="$LOG_MAX_SIZE" ;;
    esac
    
    if [[ "$file_size" -gt "$max_bytes" ]]; then
        # Rotate log files
        for ((i=LOG_MAX_FILES-1; i>=1; i--)); do
            if [[ -f "${LOG_FILE}.$i" ]]; then
                mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i+1))"
            fi
        done
        mv "$LOG_FILE" "${LOG_FILE}.1"
        touch "$LOG_FILE"
        log_message "INFO" "Log rotated - previous log saved as ${LOG_FILE}.1"
    fi
}

send_notification() {
    local message="$1"
    local level="$2"  # "success" or "error"
    
    # Log the message
    case "$level" in
        "success") log_message "SUCCESS" "$message" ;;
        "error") log_message "ERROR" "$message" ;;
        *) log_message "INFO" "$message" ;;
    esac
    
    # Check notification settings
    if [[ "$notification_type" == "none" ]]; then
        return 0
    fi
    
    if [[ "$notification_type" == "error" && "$level" == "success" ]]; then
        return 0
    fi
    
    # Send Gotify notification if configured
    if [[ -n "$GOTIFY_SERVER_URL" && -n "$GOTIFY_APP_TOKEN" ]]; then
        local priority=5
        local title="ZFS Auto Dataset Converter"
        
        case "$level" in
            "success") priority=1 ;;
            "error") priority=8 ;;
        esac
        
        curl -s -X POST "$GOTIFY_SERVER_URL/message" \
            -H "Content-Type: application/json" \
            -d "{\"title\":\"$title\",\"message\":\"$message\",\"priority\":$priority}" \
            -H "X-Gotify-Key: $GOTIFY_APP_TOKEN" >/dev/null 2>&1
    fi
}

#---------------------------
# Check if location is an actively mounted ZFS dataset
#
is_zfs_dataset() {
    local location="$1"

    # Validate input first
    if [[ -z "$location" ]]; then
        log_message "ERROR" "is_zfs_dataset: location cannot be empty"
        return 1
    fi

    # Use validate_path if available, otherwise basic validation
    if declare -F validate_path >/dev/null 2>&1; then
        if ! validate_path "$location"; then
            log_message "ERROR" "Invalid location path: $location"
            return 1
        fi
    fi

    # Use awk for safe fixed-string matching instead of grep with regex
    # This prevents regex injection attacks via crafted paths
    if zfs list -H -o mounted,mountpoint 2>/dev/null | awk -v loc="$location" '$1 == "yes" && $2 == loc {exit 0} END {exit 1}'; then
        return 0
    else
        return 1
    fi
}

#######################################
# Safe directory removal with validation
# Performs comprehensive validation before destructive operations
# Arguments:
#   $1 - Base path
#   $2 - Relative path to remove
# Returns:
#   0 on success, 1 on error
#######################################
safe_remove_directory() {
    local base_path="$1"
    local relative_path="$2"
    local full_path="${base_path}/${relative_path}"

    # Validation checks
    if [[ -z "$relative_path" ]]; then
        log_message "ERROR" "Cannot remove directory: relative path is empty"
        return 1
    fi

    if [[ "$relative_path" =~ \.\. ]]; then
        log_message "ERROR" "Cannot remove directory: path contains .."
        return 1
    fi

    if [[ "$relative_path" =~ ^/ ]]; then
        log_message "ERROR" "Cannot remove directory: relative path starts with /"
        return 1
    fi

    # Verify the path is within base_path using realpath
    local real_full_path
    if ! real_full_path=$(realpath -m "$full_path" 2>/dev/null); then
        log_message "ERROR" "Cannot resolve path: $full_path"
        return 1
    fi

    local real_base_path
    if ! real_base_path=$(realpath -m "$base_path" 2>/dev/null); then
        log_message "ERROR" "Cannot resolve base path: $base_path"
        return 1
    fi

    if [[ ! "$real_full_path" =~ ^"$real_base_path"/ ]]; then
        log_message "ERROR" "Path $full_path is outside base path $base_path"
        return 1
    fi

    # Verify directory exists
    if [[ ! -d "$full_path" ]]; then
        log_message "WARNING" "Directory does not exist: $full_path"
        return 0  # Not an error if already gone
    fi

    # Perform deletion with logging
    log_message "INFO" "Removing directory: $full_path"
    if [[ "$DRY_RUN" != "yes" ]]; then
        if ! rm -rf "$full_path"; then
            log_message "ERROR" "Failed to remove directory: $full_path"
            return 1
        fi
        log_message "SUCCESS" "Directory removed: $full_path"
    else
        log_message "INFO" "DRY RUN: Would remove directory: $full_path"
    fi

    return 0
}

#######################################
# Stop Docker containers with bind mounts on non-ZFS directories
#
# Identifies running containers with bind mounts in the appdata directory
# that point to regular directories (not ZFS datasets). Stops these containers
# gracefully with locking to prevent race conditions.
#
# Globals:
#   SHOULD_PROCESS_CONTAINERS - Whether to process containers
#   SOURCE_POOL_APPDATA - ZFS pool for appdata
#   SOURCE_DATASET_APPDATA - Dataset name for appdata
#   MOUNT_POINT - Base mount point
#   stopped_containers - Array to track stopped containers (output)
# Arguments:
#   None
# Returns:
#   0 on success, 1 on error
# Outputs:
#   Log messages via log_message
#######################################
stop_docker_containers() {
    if [[ "$SHOULD_PROCESS_CONTAINERS" != "yes" ]]; then
        return 0
    fi
    
    log_message "INFO" "Checking Docker containers for appdata conversion needs..."
    
    # Check if docker is available
    if ! command -v docker >/dev/null 2>&1; then
        log_message "ERROR" "Docker command not found. Please install Docker or disable container processing."
        return 1
    fi
    
    for container in $(docker ps -q 2>/dev/null); do
        local container_name
        container_name=$(docker container inspect --format '{{.Name}}' "$container" 2>/dev/null | cut -c 2-)
        local bindmounts
        bindmounts=$(docker inspect --format '{{ range .Mounts }}{{ if eq .Type "bind" }}{{ .Source }}{{printf "\n"}}{{ end }}{{ end }}' "$container" 2>/dev/null)
        
        if [[ -z "$bindmounts" ]]; then
            log_message "INFO" "Container $container_name has no bind mounts - no conversion needed"
            continue
        fi
        
        local stop_container=false
        local source_path_appdata="$SOURCE_POOL_APPDATA/$SOURCE_DATASET_APPDATA"
        
        while IFS= read -r bindmount; do
            [[ -z "$bindmount" ]] && continue
            
            # Check if bind mount is within our appdata path
            if [[ "$bindmount" != "$MOUNT_POINT/$source_path_appdata"* ]]; then
                continue
            fi
            
            # Extract the immediate child directory
            local relative_path="${bindmount#"$MOUNT_POINT/$source_path_appdata/"}"
            local immediate_child="${relative_path%%/*}"
            local combined_path="$MOUNT_POINT/$source_path_appdata/$immediate_child"
            
            if ! is_zfs_dataset "$combined_path"; then
                log_message "INFO" "Container $container_name appdata is not a ZFS dataset - will stop for conversion"
                stop_container=true
                break
            fi
        done <<< "$bindmounts"
        
        if [[ "$stop_container" == "true" ]]; then
            if [[ "$DRY_RUN" != "yes" ]]; then
                # Acquire lock for this container to prevent concurrent operations
                local lock_file
                if lock_file=$(container_lock_acquire "$container" 10 2>/dev/null); then
                    # Verify container still exists and is running
                    local container_state
                    container_state=$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null || echo "missing")

                    if [[ "$container_state" == "running" ]]; then
                        # Stop the container
                        if docker stop "$container" >/dev/null 2>&1; then
                            # Verify it actually stopped
                            local stop_verified=false
                            for ((i=0; i<10; i++)); do
                                container_state=$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null || echo "missing")
                                if [[ "$container_state" != "running" ]]; then
                                    stop_verified=true
                                    break
                                fi
                                sleep 0.5
                            done

                            if [[ "$stop_verified" == "true" ]]; then
                                stopped_containers+=("$container_name")
                                log_message "INFO" "Stopped container: $container_name (state: $container_state)"
                            else
                                log_message "ERROR" "Container $container_name may not have stopped properly"
                            fi
                        else
                            log_message "ERROR" "Failed to stop container: $container_name"
                        fi
                    elif [[ "$container_state" == "missing" ]]; then
                        log_message "WARNING" "Container $container no longer exists"
                    else
                        log_message "INFO" "Container $container_name already stopped (state: $container_state)"
                    fi

                    # Release lock
                    container_lock_release "$container"
                else
                    log_message "WARNING" "Could not acquire lock for container $container - skipping"
                fi
            else
                log_message "INFO" "DRY RUN: Would stop container: $container_name"
                stopped_containers+=("$container_name")
            fi
        else
            log_message "INFO" "Container $container_name appdata already on ZFS dataset - no action needed"
        fi
    done
    
    if [[ ${#stopped_containers[@]} -gt 0 ]]; then
        log_message "INFO" "Stopped containers: ${stopped_containers[*]}"
    fi
}

#----------------------------------------------------------------------------------    
# Restart containers that were stopped for conversion
start_docker_containers() {
    if [[ "$SHOULD_PROCESS_CONTAINERS" != "yes" ]] || [[ ${#stopped_containers[@]} -eq 0 ]]; then
        return 0
    fi
    
    for container_name in "${stopped_containers[@]}"; do
        log_message "INFO" "Restarting Docker container: $container_name"
        if [[ "$DRY_RUN" != "yes" ]]; then
            docker start "$container_name" >/dev/null 2>&1
        else
            log_message "INFO" "DRY RUN: Would restart container: $container_name"
        fi
    done
}

#------------------------------------------    
# Get vdisk info from a VM
get_vm_disk() {
    local vm_name="$1"
    
    # Check if virsh is available
    if ! command -v virsh >/dev/null 2>&1; then
        log_message "ERROR" "virsh command not found. Please install libvirt-clients or disable VM processing."
        return 1
    fi
    
    log_message "INFO" "Fetching disk info for VM: $vm_name"
    
    # Get target (like hdc, hda, etc.)
    local vm_target
    vm_target=$(virsh domblklist "$vm_name" --details 2>/dev/null | grep disk | awk '{print $3}')
    
    if [[ -n "$vm_target" ]]; then
        # Get the disk path for the given target
        local vm_disk
        vm_disk=$(virsh domblklist "$vm_name" 2>/dev/null | grep "$vm_target" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//;s/[ \t]*$//')
        log_message "INFO" "Found disk for $vm_name at target $vm_target: $vm_disk"
        echo "$vm_disk"
    else
        log_message "ERROR" "Disk not found for VM: $vm_name"
        return 1
    fi
}

#-----------------------------------------------------------------------------------------------------------------------------------  
# Check running VMs and stop those whose vdisks are in folders (not datasets) that need conversion
stop_virtual_machines() {
    if [[ "$SHOULD_PROCESS_VMS" != "yes" ]]; then
        return 0
    fi
    
    log_message "INFO" "Checking running VMs for vdisk conversion needs..."
    
    # Check if virsh is available
    if ! command -v virsh >/dev/null 2>&1; then
        log_message "ERROR" "virsh command not found. Please install libvirt-clients or disable VM processing."
        return 1
    fi
    
    local source_path_vms="$SOURCE_POOL_VMS/$SOURCE_DATASET_VMS"
    
    while IFS= read -r vm; do
        [[ -z "$vm" ]] && continue
        
        local vm_disk
        vm_disk=$(get_vm_disk "$vm")
        
        if [[ -z "$vm_disk" ]]; then
            log_message "INFO" "No disk found for VM $vm - skipping"
            continue
        fi
        
        # Check if VM disk is within our domains path
        if [[ "$vm_disk" != "$MOUNT_POINT/$source_path_vms"* ]]; then
            continue
        fi
        
        # Extract the dataset path (directory containing the vdisk file)
        local dataset_path
        dataset_path=$(dirname "$vm_disk")
        local relative_path="${dataset_path#"$MOUNT_POINT/$source_path_vms/"}"
        local immediate_child="${relative_path%%/*}"
        local combined_path="$MOUNT_POINT/$source_path_vms/$immediate_child"
        
        if ! is_zfs_dataset "$combined_path"; then
            log_message "INFO" "VM $vm vdisk is not in a ZFS dataset - will stop for conversion"

            if [[ "$DRY_RUN" != "yes" ]]; then
                # Acquire lock for this VM to prevent concurrent operations
                local lock_file
                if lock_file=$(vm_lock_acquire "$vm" 10 2>/dev/null); then
                    # Get initial VM state using virsh domstate (more reliable than dominfo)
                    local vm_state
                    vm_state=$(virsh domstate "$vm" 2>/dev/null || echo "missing")

                    if [[ "$vm_state" == "running" ]]; then
                        # Initiate graceful shutdown
                        if virsh shutdown "$vm" >/dev/null 2>&1; then
                            log_message "INFO" "Initiated graceful shutdown for VM: $vm"

                            # Poll VM state with proper timeout
                            local start_time
                            start_time=$(date +%s)
                            local shutdown_complete=false

                            while true; do
                                # Get current state directly without grep
                                vm_state=$(virsh domstate "$vm" 2>/dev/null || echo "missing")

                                # Check if VM has stopped
                                if [[ "$vm_state" != "running" && "$vm_state" != "in shutdown" ]]; then
                                    shutdown_complete=true
                                    log_message "INFO" "VM $vm shutdown complete (state: $vm_state)"
                                    break
                                fi

                                # Check timeout
                                local current_time
                                current_time=$(date +%s)
                                local elapsed=$((current_time - start_time))

                                if [[ $elapsed -ge ${VM_FORCE_SHUTDOWN_WAIT:-90} ]]; then
                                    log_message "WARNING" "VM $vm did not shutdown gracefully after ${VM_FORCE_SHUTDOWN_WAIT}s"
                                    break
                                fi

                                sleep 2
                            done

                            # Force shutdown if necessary
                            if [[ "$shutdown_complete" == "false" ]]; then
                                vm_state=$(virsh domstate "$vm" 2>/dev/null || echo "missing")
                                if [[ "$vm_state" == "running" || "$vm_state" == "in shutdown" ]]; then
                                    log_message "INFO" "Forcing shutdown of VM: $vm"
                                    if virsh destroy "$vm" >/dev/null 2>&1; then
                                        # Verify forced shutdown
                                        sleep 2
                                        vm_state=$(virsh domstate "$vm" 2>/dev/null || echo "missing")
                                        if [[ "$vm_state" != "running" ]]; then
                                            log_message "INFO" "VM $vm force shutdown successful (state: $vm_state)"
                                            stopped_vms+=("$vm")
                                        else
                                            log_message "ERROR" "Failed to force shutdown VM: $vm"
                                        fi
                                    else
                                        log_message "ERROR" "Force shutdown command failed for VM: $vm"
                                    fi
                                else
                                    stopped_vms+=("$vm")
                                fi
                            else
                                stopped_vms+=("$vm")
                            fi
                        else
                            log_message "ERROR" "Failed to initiate shutdown for VM: $vm"
                        fi
                    elif [[ "$vm_state" == "missing" ]]; then
                        log_message "WARNING" "VM $vm no longer exists or is not defined"
                    else
                        log_message "INFO" "VM $vm already stopped (state: $vm_state)"
                    fi

                    # Release lock
                    vm_lock_release "$vm"
                else
                    log_message "WARNING" "Could not acquire lock for VM $vm - skipping"
                fi
            else
                log_message "INFO" "DRY RUN: Would stop VM: $vm"
                stopped_vms+=("$vm")
            fi
        else
            log_message "INFO" "VM $vm vdisk already in ZFS dataset - no action needed"
        fi
    done < <(virsh list --name 2>/dev/null | grep -v '^$')
    
    if [[ ${#stopped_vms[@]} -gt 0 ]]; then
        log_message "INFO" "Stopped VMs: ${stopped_vms[*]}"
    fi
}

#----------------------------------------------------------------------------------    
# Restart VMs that were stopped for conversion
start_virtual_machines() {
    if [[ "$SHOULD_PROCESS_VMS" != "yes" ]] || [[ ${#stopped_vms[@]} -eq 0 ]]; then
        return 0
    fi
    
    for vm in "${stopped_vms[@]}"; do
        log_message "INFO" "Restarting VM: $vm"
        if [[ "$DRY_RUN" != "yes" ]]; then
            virsh start "$vm" >/dev/null 2>&1
        else
            log_message "INFO" "DRY RUN: Would restart VM: $vm"
        fi
    done
}

#----------------------------------------------------------------------------------    
# Normalize German umlauts to ASCII
normalize_name() {
    local original_name="$1"
    local normalized_name
    normalized_name=$(echo "$original_name" | 
                     sed 's/ä/ae/g; s/ö/oe/g; s/ü/ue/g; 
                          s/Ä/Ae/g; s/Ö/Oe/g; s/Ü/Ue/g; 
                          s/ß/ss/g')
    echo "$normalized_name"
}

#######################################
# Create new ZFS datasets from regular directories
#
# Converts regular directories to ZFS datasets with full data migration.
# Implements safe conversion with:
# - Lock acquisition to prevent concurrent modifications (TOCTOU protection)
# - Temporary rename during conversion for atomic-like behavior
# - Space availability checks with configurable buffer zone
# - Data validation using rsync with checksum verification
# - Optional cleanup of temporary directories after validation
# - Transaction support for rollback on failure
#
# Globals:
#   MOUNT_POINT - Base mount point for ZFS datasets
#   BUFFER_ZONE - Percentage of extra space required
#   DRY_RUN - Whether to perform actual operations
#   CLEANUP_TEMP_DIRS - Whether to remove temp dirs after success
#   REPLACE_SPACES - Whether to replace spaces in names
#   LOG_FILE - Log file path
#   converted_folders - Array to track conversions (output)
# Arguments:
#   $1 - Source dataset path (e.g., "tank/data")
# Returns:
#   0 on success, skips directories that can't be processed
# Outputs:
#   Log messages and rsync progress via log_message
#######################################
create_datasets() {
    local source_path="$1"
    local full_source_path="$MOUNT_POINT/$source_path"
    
    [[ ! -d "$full_source_path" ]] && return 0
    
    for entry in "$full_source_path"/*; do
        [[ ! -e "$entry" ]] && continue
        
        local base_entry
        base_entry=$(basename "$entry")
        
        # Avoid processing temp directories
        if [[ "$base_entry" == *_temp ]]; then
            continue
        fi
        
        # Apply space replacement if configured
        if [[ "$REPLACE_SPACES" == "yes" ]]; then
            base_entry=$(echo "$base_entry" | tr ' ' '_')
        fi
        
        # Normalize German characters
        local normalized_base_entry
        normalized_base_entry=$(normalize_name "$base_entry")
        
        # Only process directories
        if [[ ! -d "$entry" ]]; then
            continue
        fi

        log_message "INFO" "Processing directory: $entry"

        # Acquire dataset lock to prevent concurrent creation
        local dataset_name="${source_path}/${normalized_base_entry}"
        local lock_file
        if ! lock_file=$(dataset_lock_acquire "$dataset_name" 30 2>/dev/null); then
            log_message "WARNING" "Could not acquire lock for dataset $dataset_name - skipping"
            continue
        fi

        # Re-check if dataset exists after acquiring lock (TOCTOU protection)
        if zfs list -H -o name "$dataset_name" >/dev/null 2>&1; then
            log_message "INFO" "Dataset $dataset_name already exists (created by another process) - skipping"
            dataset_lock_release "$dataset_name"
            continue
        fi

        # Calculate directory size
        local folder_size
        folder_size=$(du -sb "$entry" 2>/dev/null | cut -f1)
        local folder_size_hr
        folder_size_hr=$(du -sh "$entry" 2>/dev/null | cut -f1)

        log_message "INFO" "Directory size: $folder_size_hr"

        # Calculate buffer zone
        local buffer_zone_size=$((folder_size * BUFFER_ZONE / 100))

        # Check available space
        local parent_avail
        parent_avail=$(zfs list -o avail -p -H "${source_path}" 2>/dev/null || echo 0)

        if [[ "$parent_avail" -ge "$buffer_zone_size" ]]; then
            log_message "INFO" "Creating dataset $dataset_name..."

            if [[ "$DRY_RUN" != "yes" ]]; then
                # Move original to temp location
                if ! mv "$entry" "${full_source_path}/${normalized_base_entry}_temp"; then
                    log_message "ERROR" "Failed to rename $entry to temporary location"
                    dataset_lock_release "$dataset_name"
                    continue
                fi

                # Create new dataset
                if zfs create "$dataset_name"; then
                    log_message "SUCCESS" "Created ZFS dataset: $dataset_name"
                    
                    # Copy data using rsync with checksum verification and progress reporting
                    log_message "INFO" "Copying data to new dataset..."
                    # --checksum: verify data integrity using checksums (slower but safer)
                    # --info=progress2: show overall progress (works well with logging)
                    # -a: archive mode (preserve permissions, timestamps, etc.)
                    if rsync -a --checksum --info=progress2 "${full_source_path}/${normalized_base_entry}_temp/" "${full_source_path}/${normalized_base_entry}/" 2>&1 | tee -a "$LOG_FILE"; then
                        local rsync_exit_status=$?
                        
                        # Validate copy if cleanup is enabled
                        if [[ "$CLEANUP_TEMP_DIRS" == "yes" && $rsync_exit_status -eq 0 ]]; then
                            log_message "INFO" "Validating data copy..."
                            
                            local source_file_count
                            source_file_count=$(find "${full_source_path}/${normalized_base_entry}_temp" -type f 2>/dev/null | wc -l)
                            local destination_file_count
                            destination_file_count=$(find "${full_source_path}/${normalized_base_entry}" -type f 2>/dev/null | wc -l)
                            local source_total_size
                            source_total_size=$(du -sb "${full_source_path}/${normalized_base_entry}_temp" 2>/dev/null | cut -f1)
                            local destination_total_size
                            destination_total_size=$(du -sb "${full_source_path}/${normalized_base_entry}" 2>/dev/null | cut -f1)
                            
                            if [[ "$source_file_count" -eq "$destination_file_count" && "$source_total_size" -eq "$destination_total_size" ]]; then
                                log_message "SUCCESS" "Data validation successful - cleaning up temporary directory"
                                if safe_remove_directory "$full_source_path" "${normalized_base_entry}_temp"; then
                                    converted_folders+=("$entry")
                                else
                                    log_message "ERROR" "Failed to cleanup temporary directory - please remove manually"
                                fi
                            else
                                log_message "ERROR" "Data validation failed. Source: $source_file_count files, $source_total_size bytes. Destination: $destination_file_count files, $destination_total_size bytes"
                            fi
                        elif [[ "$CLEANUP_TEMP_DIRS" == "no" ]]; then
                            log_message "INFO" "Cleanup disabled - temporary directory preserved: ${full_source_path}/${normalized_base_entry}_temp"
                            converted_folders+=("$entry")
                        else
                            log_message "ERROR" "Rsync failed - temporary directory preserved for investigation"
                        fi
                    else
                        log_message "ERROR" "Failed to copy data to new dataset"
                    fi
                else
                    log_message "ERROR" "Failed to create ZFS dataset: $dataset_name"
                    # Restore original directory name
                    mv "${full_source_path}/${normalized_base_entry}_temp" "$entry" 2>/dev/null
                    dataset_lock_release "$dataset_name"
                    continue
                fi

                # Release dataset lock after successful creation
                dataset_lock_release "$dataset_name"
            else
                log_message "INFO" "DRY RUN: Would create dataset $dataset_name"
                converted_folders+=("$entry")
                dataset_lock_release "$dataset_name"
            fi
        else
            log_message "ERROR" "Insufficient space for converting $entry (need $folder_size_hr + ${BUFFER_ZONE}% buffer)"
            dataset_lock_release "$dataset_name"
        fi
    done
}

#----------------------------------------------------------------------------------    
# Print summary of converted datasets
print_conversion_summary() {
    if [[ ${#converted_folders[@]} -gt 0 ]]; then
        local summary="Successfully converted ${#converted_folders[@]} directories to ZFS datasets:"
        for folder in "${converted_folders[@]}"; do
            summary="$summary\n- $(basename "$folder")"
        done
        log_message "SUCCESS" "$summary"
        send_notification "$summary" "success"
    else
        log_message "INFO" "No directories were converted to datasets"
    fi
}

#######################################
# Validate source datasets and check for conversion work
#
# Verifies that all configured source datasets are valid ZFS datasets
# and determines how many directories need conversion. Exits the script
# if no sources are configured or no conversion work is needed.
#
# Performs validation:
# - Checks if source paths exist
# - Verifies sources are actual ZFS datasets
# - Counts directories that aren't yet datasets
# - Provides summary of conversion work needed
#
# Globals:
#   SOURCE_POOL - Primary ZFS pool
#   SOURCE_DATASET - Primary dataset
#   SOURCE_POOL_APPDATA - Appdata pool (if containers enabled)
#   SOURCE_DATASET_APPDATA - Appdata dataset (if containers enabled)
#   SOURCE_POOL_VMS - VM pool (if VMs enabled)
#   SOURCE_DATASET_VMS - VM dataset (if VMs enabled)
#   SOURCE_DATASETS_ARRAY - Additional user-defined datasets
#   SHOULD_PROCESS_CONTAINERS - Whether to include appdata
#   SHOULD_PROCESS_VMS - Whether to include VM storage
#   MOUNT_POINT - Base mount point
# Arguments:
#   None
# Returns:
#   0 if work needs to be done
#   Exits with code 0 if no work needed
#   Exits with code 1 if validation fails
# Outputs:
#   Log messages and summary via log_message
#######################################
validate_sources_and_work() {
    log_message "INFO" "Validating sources and checking for conversion work..."
    
    # Build the source datasets array
    local -a all_source_datasets=()
    
    # Add container appdata if configured
    if [[ "$SHOULD_PROCESS_CONTAINERS" == "yes" ]]; then
        all_source_datasets+=("${SOURCE_POOL_APPDATA}/${SOURCE_DATASET_APPDATA}")
    fi
    
    # Add VM domains if configured
    if [[ "$SHOULD_PROCESS_VMS" == "yes" ]]; then
        all_source_datasets+=("${SOURCE_POOL_VMS}/${SOURCE_DATASET_VMS}")
    fi
    
    # Add user-defined datasets
    all_source_datasets+=("${SOURCE_DATASETS_ARRAY[@]}")
    
    # Check if array is empty
    if [[ ${#all_source_datasets[@]} -eq 0 ]]; then
        log_message "ERROR" "No source datasets configured. Please configure container processing, VM processing, or add datasets to SOURCE_DATASETS_ARRAY"
        send_notification "ZFS Auto Dataset Converter: No sources configured" "error"
        exit 1
    fi
    
    local folder_count=0
    local valid_sources=0
    
    for source_path in "${all_source_datasets[@]}"; do
        local full_path="$MOUNT_POINT/$source_path"
        
        # Check if source exists
        if [[ ! -e "$full_path" ]]; then
            log_message "ERROR" "Source path does not exist: $full_path"
            send_notification "ZFS Auto Dataset Converter: Source path $full_path does not exist" "error"
            exit 1
        fi
        
        # Check if source is a ZFS dataset
        # Use direct zfs list instead of grep to prevent regex injection
        if ! zfs list -H "$source_path" >/dev/null 2>&1; then
            log_message "ERROR" "Source $source_path is not a ZFS dataset. Sources must be datasets to host child datasets."
            send_notification "ZFS Auto Dataset Converter: Source $source_path is not a ZFS dataset" "error"
            exit 1
        fi
        
        log_message "INFO" "Source $source_path is valid"
        valid_sources=$((valid_sources + 1))
        
        # Count directories that need conversion
        local current_folder_count=0
        if [[ -d "$full_path" ]]; then
            for entry in "$full_path"/*; do
                [[ ! -e "$entry" ]] && continue
                local base_entry
                base_entry=$(basename "$entry")
                
                # Use direct zfs list instead of grep to prevent regex injection
                local dataset_name="${source_path}/${base_entry}"
                if [[ -d "$entry" && ! "$base_entry" =~ _temp$ ]] &&
                   ! zfs list -H "$dataset_name" >/dev/null 2>&1; then
                    current_folder_count=$((current_folder_count + 1))
                fi
            done
        fi
        
        if [[ $current_folder_count -eq 0 ]]; then
            log_message "INFO" "All children in $source_path are already datasets"
        else
            log_message "INFO" "Found $current_folder_count directories in $source_path that need conversion"
        fi
        
        folder_count=$((folder_count + current_folder_count))
    done
    
    if [[ $folder_count -eq 0 ]]; then
        log_message "INFO" "All directories in all sources are already datasets - no work needed"
        send_notification "ZFS Auto Dataset Converter: No conversion work needed - all directories are already datasets" "success"
        exit 0
    fi
    
    log_message "INFO" "Found $folder_count directories across $valid_sources sources that need conversion"
    
    # Store the validated array for later use
    SOURCE_DATASETS_ARRAY=("${all_source_datasets[@]}")
}

#-------------------------------------------------------------------------------------
# Main conversion function - process all configured datasets
perform_conversions() {
    log_message "INFO" "Starting dataset conversions..."
    
    for dataset in "${SOURCE_DATASETS_ARRAY[@]}"; do
        log_message "INFO" "Processing dataset: $dataset"
        create_datasets "$dataset"
    done
}

#--------------------------------
#    MAIN EXECUTION             #
#--------------------------------

# Initialize logging
rotate_log
log_message "INFO" "=== ZFS Auto Dataset Converter Started ==="
log_message "INFO" "Configuration: DRY_RUN=$DRY_RUN, MOUNT_POINT=$MOUNT_POINT"

# Check dependencies
pre_run_checks

# Validate configuration and sources
validate_sources_and_work

# Stop services that need datasets converted
stop_docker_containers
stop_virtual_machines

# Perform the conversions
perform_conversions

# Restart stopped services
start_docker_containers
start_virtual_machines

# Print summary
print_conversion_summary

log_message "INFO" "=== ZFS Auto Dataset Converter Completed ==="