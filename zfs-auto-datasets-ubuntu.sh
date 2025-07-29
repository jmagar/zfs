#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# #   Script for watching ZFS datasets and auto converting regular folders to datasets                                                  # #
# #   Ubuntu-compatible version with Gotify notifications and file logging                                                             # # 
# #   Adapted from SpaceInvaderOne's original Unraid script                                                                            # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the shared configuration file
if [[ -f "$SCRIPT_DIR/zfs-config.sh" ]]; then
    source "$SCRIPT_DIR/zfs-config.sh"
else
    echo "ERROR: Cannot find zfs-config.sh in $SCRIPT_DIR" >&2
    echo "Please ensure zfs-config.sh exists in the same directory as this script." >&2
    exit 1
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

# Logging and notification functions
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
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
        file_size=$(ls -la "$LOG_FILE" 2>/dev/null | awk '{print $5}' || echo 0)
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
    
    if zfs list -H -o mounted,mountpoint | grep -q "^yes"$'\t'"$location$"; then
        return 0
    else
        return 1
    fi
}

#-----------------------------------------------------------------------------------------------------------------------------------  #
# Check running containers and stop those whose bind mounts are folders (not datasets) that need conversion                       #
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
        local container_name=$(docker container inspect --format '{{.Name}}' "$container" 2>/dev/null | cut -c 2-)
        local bindmounts=$(docker inspect --format '{{ range .Mounts }}{{ if eq .Type "bind" }}{{ .Source }}{{printf "\n"}}{{ end }}{{ end }}' "$container" 2>/dev/null)
        
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
            local relative_path="${bindmount#$MOUNT_POINT/$source_path_appdata/}"
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
                docker stop "$container" >/dev/null 2>&1
                stopped_containers+=("$container_name")
                log_message "INFO" "Stopped container: $container_name"
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
    local vm_target=$(virsh domblklist "$vm_name" --details 2>/dev/null | grep disk | awk '{print $3}')
    
    if [[ -n "$vm_target" ]]; then
        # Get the disk path for the given target
        local vm_disk=$(virsh domblklist "$vm_name" 2>/dev/null | grep "$vm_target" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//;s/[ \t]*$//')
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
        local dataset_path=$(dirname "$vm_disk")
        local relative_path="${dataset_path#$MOUNT_POINT/$source_path_vms/}"
        local immediate_child="${relative_path%%/*}"
        local combined_path="$MOUNT_POINT/$source_path_vms/$immediate_child"
        
        if ! is_zfs_dataset "$combined_path"; then
            log_message "INFO" "VM $vm vdisk is not in a ZFS dataset - will stop for conversion"
            
            if [[ "$DRY_RUN" != "yes" ]]; then
                virsh shutdown "$vm" >/dev/null 2>&1
                
                # Wait for VM to shutdown gracefully
                local start_time=$(date +%s)
                while virsh dominfo "$vm" 2>/dev/null | grep -q 'running'; do
                    sleep 5
                    local current_time=$(date +%s)
                    if (( current_time - start_time >= VM_FORCE_SHUTDOWN_WAIT )); then
                        log_message "INFO" "VM $vm did not shutdown gracefully after ${VM_FORCE_SHUTDOWN_WAIT}s - forcing shutdown"
                        virsh destroy "$vm" >/dev/null 2>&1
                        break
                    fi
                done
                stopped_vms+=("$vm")
                log_message "INFO" "Stopped VM: $vm"
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

#----------------------------------------------------------------------------------    
# Create new ZFS datasets from regular directories
create_datasets() {
    local source_path="$1"
    local full_source_path="$MOUNT_POINT/$source_path"
    
    [[ ! -d "$full_source_path" ]] && return 0
    
    for entry in "$full_source_path"/*; do
        [[ ! -e "$entry" ]] && continue
        
        local base_entry=$(basename "$entry")
        
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
        
        # Skip if dataset already exists
        if zfs list -o name -H | grep -qE "^${source_path}/${normalized_base_entry}$"; then
            log_message "INFO" "Dataset ${source_path}/${normalized_base_entry} already exists - skipping"
            continue
        fi
        
        # Only process directories
        if [[ ! -d "$entry" ]]; then
            continue
        fi
        
        log_message "INFO" "Processing directory: $entry"
        
        # Calculate directory size
        local folder_size
        folder_size=$(du -sb "$entry" 2>/dev/null | cut -f1)
        local folder_size_hr
        folder_size_hr=$(du -sh "$entry" 2>/dev/null | cut -f1)
        
        log_message "INFO" "Directory size: $folder_size_hr"
        
        # Calculate buffer zone
        local buffer_zone_size=$((folder_size * BUFFER_ZONE / 100))
        
        # Check available space
        if zfs list -o name -H | grep -qE "^${source_path}$" && 
           (( $(zfs list -o avail -p -H "${source_path}" 2>/dev/null || echo 0) >= buffer_zone_size )); then
            
            log_message "INFO" "Creating dataset ${source_path}/${normalized_base_entry}..."
            
            if [[ "$DRY_RUN" != "yes" ]]; then
                # Move original to temp location
                if ! mv "$entry" "${full_source_path}/${normalized_base_entry}_temp"; then
                    log_message "ERROR" "Failed to rename $entry to temporary location"
                    continue
                fi
                
                # Create new dataset
                if zfs create "${source_path}/${normalized_base_entry}"; then
                    log_message "SUCCESS" "Created ZFS dataset: ${source_path}/${normalized_base_entry}"
                    
                    # Copy data using rsync
                    log_message "INFO" "Copying data to new dataset..."
                    if rsync -a "${full_source_path}/${normalized_base_entry}_temp/" "${full_source_path}/${normalized_base_entry}/"; then
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
                                rm -rf "${full_source_path}/${normalized_base_entry}_temp"
                                converted_folders+=("$entry")
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
                    log_message "ERROR" "Failed to create ZFS dataset: ${source_path}/${normalized_base_entry}"
                    # Restore original directory name
                    mv "${full_source_path}/${normalized_base_entry}_temp" "$entry" 2>/dev/null
                fi
            else
                log_message "INFO" "DRY RUN: Would create dataset ${source_path}/${normalized_base_entry}"
                converted_folders+=("$entry")
            fi
        else
            log_message "ERROR" "Insufficient space for converting $entry (need $folder_size_hr + ${BUFFER_ZONE}% buffer)"
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

#----------------------------------------------------------------------------------    
# Check if there's any work to do and validate sources
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
        if ! zfs list -o name -H | grep -qE "^${source_path}$"; then
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
                local base_entry=$(basename "$entry")
                
                if [[ -d "$entry" && ! "$base_entry" =~ _temp$ ]] && 
                   ! zfs list -o name -H | grep -qE "^${source_path}/${base_entry}$"; then
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