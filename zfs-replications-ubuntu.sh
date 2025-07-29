#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# #   Script for ZFS dataset snapshotting and replication (local or remote)                                                          # #
# #   Ubuntu-compatible version with Gotify notifications and file logging                                                          # # 
# #   Adapted from SpaceInvaderOne's original Unraid script                                                                         # # 
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

# Global variables for current dataset being processed
current_source_path=""
current_zfs_destination_path=""
current_destination_rsync_location=""
current_sanoid_config_path=""
tune="1"  # For different notification tunes

#--------------------------------
#     FUNCTIONS START HERE      #
#--------------------------------

# Logging and notification functions (shared with auto-datasets script)
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Write to log file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Color codes for prettier output
    local color=""
    local reset="\033[0m"
    case "$level" in
        "SUCCESS") color="\033[1;32m" ;;  # Bold green
        "ERROR")   color="\033[1;31m" ;;  # Bold red
        "INFO")    color="\033[1;34m" ;;  # Bold blue
        "WARNING") color="\033[1;33m" ;;  # Bold yellow
    esac
    
    # Print to stdout with colors
    echo -e "${color}[$level]${reset} $message"
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
        local title="ZFS Snapshot & Replication"
        
        case "$level" in
            "success") priority=1 ;;
            "error") priority=8 ;;
        esac
        
        log_message "INFO" "Sending Gotify notification: $title"
        
        # Create proper JSON payload using jq
        local json_payload
        json_payload=$(jq -n \
            --arg title "$title" \
            --arg message "$message" \
            --argjson priority "$priority" \
            '{title: $title, message: $message, priority: $priority}')
        
        local response
        response=$(curl -s -X POST "$GOTIFY_SERVER_URL/message" \
            -H "Content-Type: application/json" \
            -d "$json_payload" \
            -H "X-Gotify-Key: $GOTIFY_APP_TOKEN" 2>&1)
        
        if [[ $? -eq 0 ]]; then
            log_message "SUCCESS" "Gotify notification delivered successfully"
        else
            log_message "ERROR" "Gotify notification failed: $response"
        fi
    else
        log_message "INFO" "Gotify not configured - skipping notification"
    fi
}

#
####################
#
# Pre-run checks for dependencies and configuration
pre_run_checks() {
    log_message "INFO" "Performing pre-run checks for dataset: $current_source_path"
    
    # Check for essential utilities
    if ! command -v zfs >/dev/null 2>&1; then
        local msg='ZFS utilities not found. Please install zfsutils-linux package.'
        send_notification "$msg" "error"
        exit 1
    fi
    
    # Check for Sanoid if auto snapshots are enabled
    if [[ "$AUTO_SNAPSHOTS" == "yes" ]] && [[ ! -x "$SANOID_BINARY" ]]; then
        log_message "ERROR" "Sanoid not found at $SANOID_BINARY"
        echo -e "\033[1;33m[PROMPT]\033[0m Would you like to install Sanoid? (Y/n): "
        read -r response
        if [[ "$response" =~ ^[Nn]$ ]]; then
            local msg="Sanoid not found. Please install Sanoid manually or disable auto snapshots."
            send_notification "$msg" "error"
            exit 1
        else
            log_message "INFO" "Installing Sanoid..."
            sudo apt update && sudo apt install -y sanoid
            if [[ ! -x "$SANOID_BINARY" ]]; then
                local msg="Failed to install Sanoid. Please install manually: sudo apt install sanoid"
                send_notification "$msg" "error"
                exit 1
            fi
            log_message "SUCCESS" "Sanoid installed successfully"
        fi
    fi
    
    # Check for Syncoid if ZFS replication is enabled
    if [[ "$REPLICATION" == "zfs" ]] && [[ ! -x "$SYNCOID_BINARY" ]]; then
        local msg="Syncoid not found at $SYNCOID_BINARY. Please install Syncoid or change replication method."
        send_notification "$msg" "error"
        exit 1
    fi
    
    # Check for rsync if rsync replication is enabled
    if [[ "$REPLICATION" == "rsync" ]] && ! command -v rsync >/dev/null 2>&1; then
        local msg="rsync not found. Please install rsync package for rsync replication."
        send_notification "$msg" "error"
        exit 1
    fi
    
    # Check if the source dataset exists
    if ! zfs list -H "$current_source_path" &>/dev/null; then
        local msg="Source dataset '$current_source_path' does not exist."
        send_notification "$msg" "error"
        exit 1
    fi
    
    # Check if auto snapshots is enabled and source dataset has spaces
    if [[ "$AUTO_SNAPSHOTS" == "yes" && "$current_source_path" == *" "* ]]; then
        local msg="Auto snapshots enabled but dataset name '$current_source_path' contains spaces. Sanoid config cannot handle spaces in dataset names."
        send_notification "$msg" "error"
        exit 1
    fi
    
    # Check if dataset is empty
    local used
    used=$(zfs get -H -o value used "$current_source_path" 2>/dev/null)
    if [[ "$used" == "0B" ]]; then
        local msg="Source dataset '$current_source_path' is empty. Nothing to replicate."
        send_notification "$msg" "error"
        return 1
    fi
    
    # Check remote server connectivity if needed
    if [[ "$DESTINATION_REMOTE" == "yes" ]]; then
        log_message "INFO" "Testing remote server connectivity..."
        if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_SERVER}" echo 'SSH connection successful' &>/dev/null; then
            local msg='SSH connection to remote server failed. Please check server details and ensure SSH keys are configured.'
            send_notification "$msg" "error"
            exit 1
        fi
        log_message "INFO" "Remote server connectivity verified"
    fi
    
    # Validate configuration variables
    case "$REPLICATION" in
        "zfs"|"rsync"|"none") ;;
        *) 
            local msg="Invalid replication method '$REPLICATION'. Must be 'zfs', 'rsync', or 'none'."
            send_notification "$msg" "error"
            exit 1
            ;;
    esac
    
    case "$AUTO_SNAPSHOTS" in
        "yes"|"no") ;;
        *)
            local msg="Invalid AUTO_SNAPSHOTS value '$AUTO_SNAPSHOTS'. Must be 'yes' or 'no'."
            send_notification "$msg" "error"
            exit 1
            ;;
    esac
    
    case "$DESTINATION_REMOTE" in
        "yes"|"no") ;;
        *)
            local msg="Invalid DESTINATION_REMOTE value '$DESTINATION_REMOTE'. Must be 'yes' or 'no'."
            send_notification "$msg" "error"
            exit 1
            ;;
    esac
    
    # Check remote server variables if remote replication is enabled
    if [[ "$DESTINATION_REMOTE" == "yes" ]]; then
        if [[ -z "$REMOTE_USER" || -z "$REMOTE_SERVER" ]]; then
            local msg="Remote replication enabled but REMOTE_USER or REMOTE_SERVER not configured."
            send_notification "$msg" "error"
            exit 1
        fi
    fi
    
    # Check if both replication and snapshots are disabled
    if [[ "$REPLICATION" == "none" && "$AUTO_SNAPSHOTS" == "no" ]]; then
        local msg='Both replication and auto snapshots are disabled. Please configure at least one.'
        send_notification "$msg" "error"
        exit 1
    fi
    
    # Check rsync type if rsync replication is enabled
    if [[ "$REPLICATION" == "rsync" ]]; then
        case "$RSYNC_TYPE" in
            "incremental"|"mirror") ;;
            *)
                local msg="Invalid RSYNC_TYPE '$RSYNC_TYPE'. Must be 'incremental' or 'mirror'."
                send_notification "$msg" "error"
                exit 1
                ;;
        esac
    fi
    
    log_message "INFO" "Pre-run checks completed successfully"
}

#
####################
#
# Create Sanoid configuration file for the current dataset
create_sanoid_config() {
    # Only create config if auto snapshots are enabled
    if [[ "$AUTO_SNAPSHOTS" != "yes" ]]; then
        return 0
    fi
    
    log_message "INFO" "Creating Sanoid configuration for: $current_source_path"
    
    # Ensure the configuration directory exists
    if [[ ! -d "$current_sanoid_config_path" ]]; then
        sudo mkdir -p "$current_sanoid_config_path"
    fi
    
    # Copy default configuration if it doesn't exist
    local defaults_file="$current_sanoid_config_path/sanoid.defaults.conf"
    if [[ ! -f "$defaults_file" ]]; then
        if [[ -f "/etc/sanoid/sanoid.defaults.conf" ]]; then
            sudo cp "/etc/sanoid/sanoid.defaults.conf" "$defaults_file"
        else
            log_message "WARNING" "Default Sanoid configuration not found at /etc/sanoid/sanoid.defaults.conf"
        fi
    fi
    
    # Check if configuration file already exists
    local config_file="$current_sanoid_config_path/sanoid.conf"
    if [[ -f "$config_file" ]]; then
        log_message "INFO" "Sanoid configuration already exists: $config_file"
        return 0
    fi
    
    # Create the configuration file
    sudo tee "$config_file" > /dev/null << EOF
[$current_source_path]
use_template = production
recursive = yes

[template_production]
hourly = $SNAPSHOT_HOURS
daily = $SNAPSHOT_DAYS
weekly = $SNAPSHOT_WEEKS
monthly = $SNAPSHOT_MONTHS
yearly = $SNAPSHOT_YEARS
autosnap = yes
autoprune = yes
EOF

    log_message "SUCCESS" "Created Sanoid configuration: $config_file"
}

#
####################
#
# Create automatic snapshots using Sanoid
autosnap() {
    if [[ "$AUTO_SNAPSHOTS" != "yes" ]]; then
        log_message "INFO" "Auto snapshots disabled - skipping snapshot creation"
        return 0
    fi
    
    log_message "INFO" "Creating automatic snapshots for: $current_source_path"
    
    # Run sanoid to create snapshots
    if sudo "$SANOID_BINARY" --configdir="$current_sanoid_config_path" --take-snapshots; then
        tune="2"  # Use different notification tune for snapshots
        local msg="Automatic snapshot creation successful for: $current_source_path"
        send_notification "$msg" "success"
        log_message "SUCCESS" "$msg"
    else
        local msg="Automatic snapshot creation failed for: $current_source_path"
        send_notification "$msg" "error"
        return 1
    fi
}

#
####################
#
# Prune old snapshots using Sanoid
autoprune() {
    if [[ "$AUTO_SNAPSHOTS" != "yes" ]]; then
        log_message "INFO" "Auto snapshots disabled - skipping snapshot pruning"
        return 0
    fi
    
    log_message "INFO" "Pruning old snapshots for: $current_source_path"
    
    # Run sanoid to prune snapshots based on retention policy
    sudo "$SANOID_BINARY" --configdir="$current_sanoid_config_path" --prune-snapshots
    
    log_message "INFO" "Snapshot pruning completed for: $current_source_path"
}

#
####################
#
# Perform ZFS replication using Syncoid
zfs_replication() {
    if [[ "$REPLICATION" != "zfs" ]]; then
        log_message "INFO" "ZFS replication not enabled - skipping"
        return 0
    fi
    
    log_message "INFO" "Starting ZFS replication for: $current_source_path"
    
    local destination
    
    # Configure destination based on remote/local setting
    if [[ "$DESTINATION_REMOTE" == "yes" ]]; then
        destination="${REMOTE_USER}@${REMOTE_SERVER}:${current_zfs_destination_path}"
        
        # Ensure parent destination dataset exists on remote server
        log_message "INFO" "Ensuring parent destination dataset exists on remote server"
        if ! ssh "${REMOTE_USER}@${REMOTE_SERVER}" "zfs list -o name -H '${DESTINATION_POOL}/${PARENT_DESTINATION_DATASET}' &>/dev/null || zfs create '${DESTINATION_POOL}/${PARENT_DESTINATION_DATASET}'"; then
            local msg="Failed to create parent ZFS dataset on remote server: ${DESTINATION_POOL}/${PARENT_DESTINATION_DATASET}"
            send_notification "$msg" "error"
            return 1
        fi
    else
        destination="$current_zfs_destination_path"
        
        # Ensure parent destination dataset exists locally
        log_message "INFO" "Ensuring parent destination dataset exists locally"
        if ! zfs list -o name -H "${DESTINATION_POOL}/${PARENT_DESTINATION_DATASET}" &>/dev/null; then
            if ! zfs create "${DESTINATION_POOL}/${PARENT_DESTINATION_DATASET}"; then
                local msg="Failed to create local ZFS dataset: ${DESTINATION_POOL}/${PARENT_DESTINATION_DATASET}"
                send_notification "$msg" "error"
                return 1
            fi
        fi
    fi
    
    # Configure syncoid flags based on mode
    local -a syncoid_flags=("-r")
    case "$SYNCOID_MODE" in
        "strict-mirror")
            syncoid_flags+=("--delete-target-snapshots" "--force-delete")
            ;;
        "basic")
            # No additional flags
            ;;
        *)
            local msg="Invalid SYNCOID_MODE '$SYNCOID_MODE'. Must be 'strict-mirror' or 'basic'."
            send_notification "$msg" "error"
            return 1
            ;;
    esac
    
    log_message "INFO" "Running Syncoid with mode: $SYNCOID_MODE"
    
    # Perform the replication
    if [[ "$DRY_RUN" != "yes" ]]; then
        # Run syncoid as the original user to use their SSH keys, but with sudo for ZFS operations
        local run_user="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"
        if sudo -u "$run_user" "$SYNCOID_BINARY" "${syncoid_flags[@]}" "$current_source_path" "$destination"; then
            local msg="ZFS replication successful from $current_source_path to $destination"
            send_notification "$msg" "success"
            log_message "SUCCESS" "$msg"
        else
            local msg="ZFS replication failed from $current_source_path to $destination"
            send_notification "$msg" "error"
            return 1
        fi
    else
        log_message "INFO" "DRY RUN: Testing ZFS replication connection to $destination"
        
        # Test remote ZFS accessibility
        if [[ "$DESTINATION_REMOTE" == "yes" ]]; then
            local remote_test
            if remote_test=$(ssh "${REMOTE_USER}@${REMOTE_SERVER}" "zfs list -o name -H '${DESTINATION_POOL}' 2>/dev/null"); then
                log_message "SUCCESS" "DRY RUN: Remote ZFS pool '$DESTINATION_POOL' is accessible"
            else
                log_message "WARNING" "DRY RUN: Remote ZFS pool '$DESTINATION_POOL' is not accessible"
            fi
        else
            if zfs list -o name -H "$DESTINATION_POOL" &>/dev/null; then
                log_message "SUCCESS" "DRY RUN: Local ZFS pool '$DESTINATION_POOL' is accessible"
            else
                log_message "WARNING" "DRY RUN: Local ZFS pool '$DESTINATION_POOL' is not accessible"
            fi
        fi
        
        local msg="DRY RUN: ZFS replication would run from $current_source_path to $destination"
        log_message "INFO" "$msg"
    fi
}

#
####################
#
# Get the most recent backup directory for incremental rsync
get_previous_backup() {
    local previous_backup=""
    
    if [[ "$RSYNC_TYPE" == "incremental" ]]; then
        if [[ "$DESTINATION_REMOTE" == "yes" ]]; then
            previous_backup=$(ssh "${REMOTE_USER}@${REMOTE_SERVER}" "ls '$current_destination_rsync_location' 2>/dev/null | sort -r | head -n 2 | tail -n 1" 2>/dev/null || echo "")
        else
            if [[ -d "$current_destination_rsync_location" ]]; then
                previous_backup=$(ls "$current_destination_rsync_location" 2>/dev/null | sort -r | head -n 2 | tail -n 1 || echo "")
            fi
        fi
    fi
    
    echo "$previous_backup"
}

#
####################
#
# Perform rsync replication
rsync_replication() {
    if [[ "$REPLICATION" != "rsync" ]]; then
        log_message "INFO" "Rsync replication not enabled - skipping"
        return 0
    fi
    
    log_message "INFO" "Starting rsync replication for: $current_source_path"
    
    local snapshot_name="rsync_snapshot_$(date +%s)"
    local backup_date
    local destination
    
    # Configure destination path based on rsync type
    if [[ "$RSYNC_TYPE" == "incremental" ]]; then
        backup_date=$(date +%Y-%m-%d_%H%M)
        destination="$current_destination_rsync_location/$backup_date"
    else
        destination="$current_destination_rsync_location"
    fi
    
    # Function to perform the actual rsync
    do_rsync() {
        local snapshot_mount_point="$1"
        local rsync_destination="$2"
        local relative_dataset_path="$3"
        
        local previous_backup
        previous_backup=$(get_previous_backup)
        
        local link_dest=""
        if [[ -n "$previous_backup" && "$RSYNC_TYPE" == "incremental" ]]; then
            local link_dest_path="$current_destination_rsync_location/$previous_backup$relative_dataset_path"
            link_dest="--link-dest=$link_dest_path"
            log_message "INFO" "Using link-dest: $link_dest_path"
        fi
        
        log_message "INFO" "Performing rsync: $snapshot_mount_point -> $rsync_destination"
        
        if [[ "$DESTINATION_REMOTE" == "yes" ]]; then
            # Create remote directory if incremental
            if [[ "$RSYNC_TYPE" == "incremental" ]]; then
                ssh "${REMOTE_USER}@${REMOTE_SERVER}" "mkdir -p '$rsync_destination'" || return 1
            fi
            
            # Perform remote rsync
            if [[ "$DRY_RUN" != "yes" ]]; then
                rsync -azvh --delete $link_dest -e ssh "$snapshot_mount_point/" "${REMOTE_USER}@${REMOTE_SERVER}:$rsync_destination/"
            else
                log_message "INFO" "DRY RUN: Would run rsync -azvh --delete $link_dest -e ssh '$snapshot_mount_point/' '${REMOTE_USER}@${REMOTE_SERVER}:$rsync_destination/'"
                return 0
            fi
        else
            # Create local directory if incremental
            if [[ "$RSYNC_TYPE" == "incremental" ]]; then
                mkdir -p "$rsync_destination" || return 1
            fi
            
            # Perform local rsync
            if [[ "$DRY_RUN" != "yes" ]]; then
                rsync -avh --delete $link_dest "$snapshot_mount_point/" "$rsync_destination/"
            else
                log_message "INFO" "DRY RUN: Would run rsync -avh --delete $link_dest '$snapshot_mount_point/' '$rsync_destination/'"
                return 0
            fi
        fi
    }
    
    if [[ "$DRY_RUN" != "yes" ]]; then
        # Create temporary snapshot for rsync
        log_message "INFO" "Creating temporary snapshot: ${current_source_path}@${snapshot_name}"
        if ! zfs snapshot "${current_source_path}@${snapshot_name}"; then
            local msg="Failed to create temporary snapshot: ${current_source_path}@${snapshot_name}"
            send_notification "$msg" "error"
            return 1
        fi
        
        # Perform rsync on main dataset
        local snapshot_mount_point="$MOUNT_POINT/${current_source_path}/.zfs/snapshot/${snapshot_name}"
        if ! do_rsync "$snapshot_mount_point" "$destination" ""; then
            local msg="Rsync replication failed for: $current_source_path"
            send_notification "$msg" "error"
            zfs destroy "${current_source_path}@${snapshot_name}" 2>/dev/null
            return 1
        fi
        
        # Process child datasets
        local child_datasets
        child_datasets=$(zfs list -r -H -o name "$current_source_path" | tail -n +2)
        
        while IFS= read -r child_dataset; do
            [[ -z "$child_dataset" ]] && continue
            
            local relative_path="${child_dataset#$current_source_path/}"
            log_message "INFO" "Processing child dataset: $child_dataset"
            
            # Create snapshot for child dataset
            if zfs snapshot "${child_dataset}@${snapshot_name}"; then
                local child_snapshot_mount="$MOUNT_POINT/${child_dataset}/.zfs/snapshot/${snapshot_name}"
                local child_destination="$destination/$relative_path"
                
                do_rsync "$child_snapshot_mount" "$child_destination" "/$relative_path"
                zfs destroy "${child_dataset}@${snapshot_name}" 2>/dev/null
            fi
        done <<< "$child_datasets"
        
        # Clean up main snapshot
        log_message "INFO" "Cleaning up temporary snapshot"
        if ! zfs destroy "${current_source_path}@${snapshot_name}"; then
            local msg="Failed to delete temporary snapshot: ${current_source_path}@${snapshot_name}"
            send_notification "$msg" "error"
        fi
        
        # Success notification
        local msg="Rsync $RSYNC_TYPE replication successful from $current_source_path to $destination"
        send_notification "$msg" "success"
        log_message "SUCCESS" "$msg"
    else
        log_message "INFO" "DRY RUN: Would perform rsync replication for $current_source_path"
    fi
}

####################
#
# Update paths for specific dataset
update_paths() {
    local source_dataset_name="$1"
    
    current_source_path="$SOURCE_POOL/$source_dataset_name"
    current_zfs_destination_path="$DESTINATION_POOL/$PARENT_DESTINATION_DATASET/${SOURCE_POOL}_${source_dataset_name}"
    current_destination_rsync_location="$PARENT_DESTINATION_FOLDER/${SOURCE_POOL}_${source_dataset_name}"
    current_sanoid_config_path="$SANOID_CONFIG_DIR${SOURCE_POOL}_${source_dataset_name}"
}

#
####################
#
# Main function to process each selected dataset
run_for_each_dataset() {
    log_message "INFO" "Determining datasets to process..."
    
    # Array to hold selected dataset names
    local -a selected_source_datasets=()
    
    if [[ "$SOURCE_DATASET_AUTO_SELECT" == "no" ]]; then
        # Use only the specified dataset
        selected_source_datasets=("$SOURCE_DATASET")
        log_message "INFO" "Auto-select disabled - using specified dataset: $SOURCE_DATASET"
    else
        # Auto-select datasets based on configured rules
        log_message "INFO" "Auto-select enabled - scanning pool: $SOURCE_POOL"
        
        # Get all direct child datasets of the source pool
        while IFS= read -r dataset_path; do
            [[ -z "$dataset_path" ]] && continue
            
            # Extract just the dataset name (not the full path)
            local dataset_name="${dataset_path#$SOURCE_POOL/}"
            
            # Skip if dataset name contains a slash (not a direct child)
            [[ "$dataset_name" == *"/"* ]] && continue
            
            # Check exclusion by prefix
            if [[ -n "$SOURCE_DATASET_AUTO_SELECT_EXCLUDE_PREFIX" && 
                  "$dataset_name" == "$SOURCE_DATASET_AUTO_SELECT_EXCLUDE_PREFIX"* ]]; then
                log_message "INFO" "Excluding dataset by prefix: $dataset_name"
                continue
            fi
            
            # Check exclusion by explicit list
            local excluded=false
            for exclude_name in "${SOURCE_DATASET_AUTO_SELECT_EXCLUDES[@]}"; do
                if [[ "$dataset_name" == "$exclude_name" ]]; then
                    log_message "INFO" "Excluding dataset by explicit list: $dataset_name"
                    excluded=true
                    break
                fi
            done
            
            if [[ "$excluded" == "false" ]]; then
                selected_source_datasets+=("$dataset_name")
                log_message "INFO" "Selected dataset: $dataset_name"
            fi
        done < <(zfs list -r -o name -H "$SOURCE_POOL" 2>/dev/null | grep "^$SOURCE_POOL/[^/]*$")
    fi
    
    if [[ ${#selected_source_datasets[@]} -eq 0 ]]; then
        local msg="No datasets selected for processing. Check your configuration."
        send_notification "$msg" "error"
        exit 1
    fi
    
    log_message "INFO" "Selected ${#selected_source_datasets[@]} datasets for processing: ${selected_source_datasets[*]}"
    
    # Phase 1: Pre-run checks and config creation
    log_message "INFO" "Phase 1: Performing pre-run checks and creating configurations"
    for source_dataset_name in "${selected_source_datasets[@]}"; do
        update_paths "$source_dataset_name"
        pre_run_checks
        create_sanoid_config
    done
    
    # Phase 2: Snapshot creation
    log_message "INFO" "Phase 2: Creating snapshots"
    for source_dataset_name in "${selected_source_datasets[@]}"; do
        update_paths "$source_dataset_name"
        autosnap
    done
    
    # Phase 3: Snapshot pruning and replication
    log_message "INFO" "Phase 3: Pruning snapshots and performing replication"
    for source_dataset_name in "${selected_source_datasets[@]}"; do
        update_paths "$source_dataset_name"
        autoprune
        rsync_replication
        zfs_replication
    done
    
    log_message "SUCCESS" "All datasets processed successfully"
}

#
########################################
#
# Main execution
main() {
    # Initialize logging
    rotate_log
    echo ""
    echo -e "\033[1;36m╔══════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;36m║           ZFS Snapshot & Replication                     ║\033[0m"
    echo -e "\033[1;36m╚══════════════════════════════════════════════════════════╝\033[0m"
    echo ""
    log_message "INFO" "Configuration: DRY_RUN=$DRY_RUN, SOURCE_POOL=$SOURCE_POOL, REPLICATION=$REPLICATION"
    
    # Execute the main processing function
    run_for_each_dataset
    
    echo ""
    echo -e "\033[1;36m╔══════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;36m║              Replication Complete                        ║\033[0m"
    echo -e "\033[1;36m╚══════════════════════════════════════════════════════════╝\033[0m"
    echo ""
}

# Execute main function
main "$@"