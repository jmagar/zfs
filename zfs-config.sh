#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# #   Shared configuration file for ZFS management scripts                                                                              # #
# #   Source this file in both zfs-auto-datasets.sh and zfs-replications.sh                                                          # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Load environment variables from .env file if it exists
SCRIPT_DIR_CONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR_CONFIG/.env" ]]; then
    source "$SCRIPT_DIR_CONFIG/.env"
elif [[ -f "$SCRIPT_DIR_CONFIG/.env.example" ]]; then
    echo "WARNING: .env file not found. Please copy .env.example to .env and configure your settings."
    echo "Using placeholder values - notifications and remote replication will not work."
fi 

# ---------------------------------------
# CORE ZFS SETTINGS
# ---------------------------------------

# Mount point base (where ZFS datasets are mounted)
MOUNT_POINT="/mnt"                         # Base mount point for ZFS datasets

# Dry run setting (applies to both scripts)
DRY_RUN="no"                             # Set to "yes" for testing, "no" for actual execution

# Primary ZFS pools and datasets
SOURCE_POOL="rpool"                       # ZFS pool containing source datasets
SOURCE_DATASET="appdata"                  # Primary dataset to snapshot/replicate

# ---------------------------------------
# AUTO DATASET CONVERTER SETTINGS
# ---------------------------------------

# Docker Container Processing
SHOULD_PROCESS_CONTAINERS="yes"           # Set to "yes" to process Docker appdata
SOURCE_POOL_APPDATA="rpool"               # ZFS pool containing Docker appdata
SOURCE_DATASET_APPDATA="appdata"          # Dataset name for Docker appdata

# Virtual Machine Processing  
SHOULD_PROCESS_VMS="no"                   # Set to "yes" to process VM vdisks
SOURCE_POOL_VMS="rpool"                   # ZFS pool containing VM domains
SOURCE_DATASET_VMS="domains"              # Dataset name for VM domains
VM_FORCE_SHUTDOWN_WAIT="90"               # Seconds to wait before force stopping VM

# Additional User-Defined Datasets
# Add datasets in format "pool/dataset", one per line
SOURCE_DATASETS_ARRAY=(
    "rpool/compose"  # Docker compose files dataset
)

# Dataset Converter Options
CLEANUP_TEMP_DIRS="yes"                   # Remove temporary directories after successful conversion
REPLACE_SPACES="no"                       # Replace spaces in dataset names with underscores
BUFFER_ZONE=11                           # Percentage of extra space required before conversion

# ---------------------------------------
# SNAPSHOT & REPLICATION SETTINGS  
# ---------------------------------------

# Dataset Selection
SOURCE_DATASET_AUTO_SELECT="yes"         # "yes" to auto-select all datasets in pool
SOURCE_DATASET_AUTO_SELECT_EXCLUDE_PREFIX="backup_"  # Exclude datasets with this prefix
SOURCE_DATASET_AUTO_SELECT_EXCLUDES=(
    # List dataset names to exclude from auto-selection
    "ROOT"
    "USERDATA"
    "temp"
    "scratch"
)

# Snapshot Settings
AUTO_SNAPSHOTS="yes"                      # Enable automatic snapshots via Sanoid
SNAPSHOT_HOURS="0"                        # Number of hourly snapshots to retain
SNAPSHOT_DAYS="7"                         # Number of daily snapshots to retain  
SNAPSHOT_WEEKS="4"                        # Number of weekly snapshots to retain
SNAPSHOT_MONTHS="3"                       # Number of monthly snapshots to retain
SNAPSHOT_YEARS="0"                        # Number of yearly snapshots to retain

# Replication Method
REPLICATION="zfs"                         # "zfs", "rsync", or "none"

# ZFS Replication Settings (only needed if REPLICATION="zfs")
DESTINATION_POOL="backup"                 # Destination ZFS pool
PARENT_DESTINATION_DATASET="squirts"      # Parent dataset for replicated data
SYNCOID_MODE="strict-mirror"              # "strict-mirror" or "basic"

# Rsync Replication Settings (only needed if REPLICATION="rsync")
PARENT_DESTINATION_FOLDER="/backup"       # Parent directory for rsync backups
RSYNC_TYPE="incremental"                  # "incremental" or "mirror"

# Remote Server Configuration
DESTINATION_REMOTE="yes"                  # "yes" for remote replication, "no" for local
# REMOTE_USER and REMOTE_SERVER are loaded from .env file

# ---------------------------------------
# SCHEDULING SETTINGS
# ---------------------------------------

# Enable automatic cron job setup
ENABLE_SCHEDULING="yes"                     # Set to "yes" to automatically setup cron jobs

# Schedule for auto dataset converter (cron format: minute hour day month weekday)
# Examples: "0 2 * * *" = daily at 2 AM, "0 */6 * * *" = every 6 hours
DATASET_CONVERTER_SCHEDULE="0 2 * * *"    # Daily at 2 AM

# Schedule for snapshot & replication (cron format)
REPLICATION_SCHEDULE="0 3 * * *"          # Daily at 3 AM (after dataset conversion)

# ---------------------------------------
# NOTIFICATION & LOGGING SETTINGS
# ---------------------------------------

# Gotify Configuration
# GOTIFY_SERVER_URL and GOTIFY_APP_TOKEN are loaded from .env file
notification_type="all"                    # "all" for both success & failure, "error" for only failure, "none" for no notifications

# Logging Configuration  
LOG_FILE="logs/zfs.log"       # Path to log file
LOG_MAX_SIZE="10M"                         # Max log file size before rotation (e.g., 10M, 100K)
LOG_MAX_FILES=5                            # Number of rotated log files to keep

# ---------------------------------------
# SYSTEM PATHS & DEPENDENCIES
# ---------------------------------------

# Sanoid Configuration
SANOID_CONFIG_DIR="/etc/sanoid/"          # Directory for Sanoid configuration files
SANOID_BINARY="/usr/sbin/sanoid"          # Path to Sanoid binary
SYNCOID_BINARY="/usr/sbin/syncoid"        # Path to Syncoid binary

# ---------------------------------------
# INTERNAL VARIABLES (DO NOT MODIFY)
# ---------------------------------------

# These are set dynamically by the scripts
stopped_containers=()
stopped_vms=()
converted_folders=()

# Function to setup passwordless sudo for ZFS commands
setup_passwordless_sudo() {
    local current_user="${SUDO_USER:-$(whoami)}"
    local sudoers_file="/etc/sudoers.d/zfs-scripts"
    
    # Check if sudoers file already exists and is properly configured
    if [[ -f "$sudoers_file" ]]; then
        if sudo grep -q "$current_user.*NOPASSWD.*zfs" "$sudoers_file" 2>/dev/null; then
            echo "Passwordless sudo for ZFS commands already configured"
            return 0
        fi
    fi
    
    echo ""
    echo -e "\033[1;33m[NOTICE]\033[0m ZFS scripts require sudo privileges for automated execution."
    echo -e "\033[1;33m[PROMPT]\033[0m Would you like to configure passwordless sudo for ZFS commands? (Y/n): "
    read -r response
    if [[ "$response" =~ ^[Nn]$ ]]; then
        echo "Skipping passwordless sudo setup. You'll need to enter passwords during execution."
        return 0
    fi
    
    echo "Setting up passwordless sudo for ZFS commands..."
    
    # Create the sudoers configuration
    local sudoers_content="# ZFS Scripts - Passwordless sudo configuration
# Generated by zfs-config.sh on $(date)

# Allow $current_user to run ZFS commands without password
$current_user ALL=(ALL) NOPASSWD: /usr/sbin/zfs, /usr/sbin/zpool, /usr/sbin/sanoid, /usr/sbin/syncoid

# Allow running syncoid as the original user while keeping ZFS privileges
$current_user ALL=(ALL) NOPASSWD: /usr/bin/sudo -u $current_user /usr/sbin/syncoid

# Package management commands (for specific dependencies only)
$current_user ALL=(ALL) NOPASSWD: /usr/bin/apt update
$current_user ALL=(ALL) NOPASSWD: /usr/bin/apt install -y zfsutils-linux
$current_user ALL=(ALL) NOPASSWD: /usr/bin/apt install -y rsync
$current_user ALL=(ALL) NOPASSWD: /usr/bin/apt install -y jq
$current_user ALL=(ALL) NOPASSWD: /usr/bin/apt install -y sanoid

# File system operations that the scripts need
$current_user ALL=(ALL) NOPASSWD: /bin/mkdir -p *
$current_user ALL=(ALL) NOPASSWD: /bin/cp /etc/sanoid/sanoid.defaults.conf *
$current_user ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/sanoid/*
$current_user ALL=(ALL) NOPASSWD: /bin/chmod 440 /etc/sudoers.d/zfs-scripts
$current_user ALL=(ALL) NOPASSWD: /bin/grep * /etc/sudoers.d/zfs-scripts"
    
    # Write the sudoers file using a temporary file for safety
    local temp_file=$(mktemp)
    echo "$sudoers_content" > "$temp_file"
    
    # Validate the sudoers syntax
    if visudo -c -f "$temp_file" >/dev/null 2>&1; then
        # Copy to the actual sudoers directory
        if sudo cp "$temp_file" "$sudoers_file"; then
            sudo chmod 440 "$sudoers_file"
            echo -e "\033[1;32m[SUCCESS]\033[0m Passwordless sudo configured for ZFS commands"
            echo "Configuration saved to: $sudoers_file"
        else
            echo -e "\033[1;31m[ERROR]\033[0m Failed to create sudoers file"
            rm -f "$temp_file"
            return 1
        fi
    else
        echo -e "\033[1;31m[ERROR]\033[0m Invalid sudoers syntax generated"
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
    echo ""
}

# Function to validate configuration
validate_config() {
    local errors=0
    
    # Check required Gotify settings if notifications enabled
    if [[ "$notification_type" != "none" ]]; then
        if [[ -z "$GOTIFY_SERVER_URL" ]]; then
            echo "ERROR: GOTIFY_SERVER_URL must be set in .env file when notifications are enabled" >&2
            errors=$((errors + 1))
        fi
        if [[ -z "$GOTIFY_APP_TOKEN" ]]; then
            echo "ERROR: GOTIFY_APP_TOKEN must be set in .env file when notifications are enabled" >&2
            errors=$((errors + 1))
        fi
    fi
    
    # Check log directory exists and is writable, create if needed
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if [[ ! -d "$log_dir" ]]; then
        echo "Creating log directory: $log_dir"
        if ! mkdir -p "$log_dir" 2>/dev/null; then
            echo "ERROR: Cannot create log directory $log_dir" >&2
            errors=$((errors + 1))
        fi
    fi
    
    if [[ -d "$log_dir" && ! -w "$log_dir" ]]; then
        echo "ERROR: Log directory $log_dir is not writable" >&2
        errors=$((errors + 1))
    fi
    
    # Check mount point exists
    if [[ ! -d "$MOUNT_POINT" ]]; then
        echo "ERROR: Mount point $MOUNT_POINT does not exist" >&2
        errors=$((errors + 1))
    fi
    
    # Check remote server variables if remote replication is enabled
    if [[ "$DESTINATION_REMOTE" == "yes" ]]; then
        if [[ -z "$REMOTE_USER" || -z "$REMOTE_SERVER" ]]; then
            echo "ERROR: REMOTE_USER and REMOTE_SERVER must be set in .env file when remote replication is enabled" >&2
            errors=$((errors + 1))
        fi
    fi
    
    # Setup passwordless sudo for ZFS commands
    setup_passwordless_sudo
    
    return $errors
}

# Function to setup cron jobs
setup_cron_jobs() {
    if [[ "$ENABLE_SCHEDULING" != "yes" ]]; then
        echo "Scheduling disabled - skipping cron job setup"
        return 0
    fi
    
    # Get the directory where the config file is located
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local dataset_script="$script_dir/zfs-auto-datasets-ubuntu.sh"
    local replication_script="$script_dir/zfs-replications-ubuntu.sh"
    
    # Check if scripts exist
    if [[ ! -f "$dataset_script" ]]; then
        echo "ERROR: Dataset converter script not found: $dataset_script" >&2
        return 1
    fi
    
    if [[ ! -f "$replication_script" ]]; then
        echo "ERROR: Replication script not found: $replication_script" >&2
        return 1
    fi
    
    # Make scripts executable
    chmod +x "$dataset_script" "$replication_script"
    
    # Create temporary crontab file
    local temp_crontab=$(mktemp)
    
    # Get existing crontab (ignore errors if no crontab exists)
    crontab -l 2>/dev/null > "$temp_crontab" || true
    
    # Remove any existing entries for these scripts
    grep -v "$dataset_script\|$replication_script" "$temp_crontab" > "${temp_crontab}.new" || true
    mv "${temp_crontab}.new" "$temp_crontab"
    
    # Add new cron entries
    echo "# ZFS Auto Dataset Converter - Generated by zfs-config.sh" >> "$temp_crontab"
    echo "$DATASET_CONVERTER_SCHEDULE $dataset_script >/dev/null 2>&1" >> "$temp_crontab"
    echo "" >> "$temp_crontab"
    echo "# ZFS Snapshot & Replication - Generated by zfs-config.sh" >> "$temp_crontab"
    echo "$REPLICATION_SCHEDULE $replication_script >/dev/null 2>&1" >> "$temp_crontab"
    echo "" >> "$temp_crontab"
    
    # Install the new crontab
    if crontab "$temp_crontab"; then
        echo "SUCCESS: Cron jobs installed successfully"
        echo "  Dataset Converter: $DATASET_CONVERTER_SCHEDULE"
        echo "  Snapshot & Replication: $REPLICATION_SCHEDULE"
        echo ""
        echo "View scheduled jobs with: crontab -l"
        echo "Remove jobs with: crontab -e"
    else
        echo "ERROR: Failed to install cron jobs" >&2
        rm -f "$temp_crontab"
        return 1
    fi
    
    # Clean up
    rm -f "$temp_crontab"
}

# Function to remove cron jobs
remove_cron_jobs() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local dataset_script="$script_dir/zfs-auto-datasets-ubuntu.sh"
    local replication_script="$script_dir/zfs-replications-ubuntu.sh"
    
    # Create temporary crontab file
    local temp_crontab=$(mktemp)
    
    # Get existing crontab (ignore errors if no crontab exists)
    if crontab -l 2>/dev/null > "$temp_crontab"; then
        # Remove entries for these scripts
        grep -v "$dataset_script\|$replication_script\|# ZFS Auto Dataset Converter\|# ZFS Snapshot & Replication" "$temp_crontab" > "${temp_crontab}.new" || true
        
        # Remove empty lines at the end
        sed -i '/^$/N;/^\n$/d' "${temp_crontab}.new"
        
        # Install the cleaned crontab
        if crontab "${temp_crontab}.new"; then
            echo "SUCCESS: ZFS cron jobs removed"
        else
            echo "ERROR: Failed to update crontab" >&2
            rm -f "$temp_crontab" "${temp_crontab}.new"
            return 1
        fi
        
        rm -f "${temp_crontab}.new"
    else
        echo "No existing crontab found"
    fi
    
    # Clean up
    rm -f "$temp_crontab"
}

# Function to show current cron schedule
show_cron_schedule() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local dataset_script="$script_dir/zfs-auto-datasets-ubuntu.sh"
    local replication_script="$script_dir/zfs-replications-ubuntu.sh"
    
    echo "Current ZFS script schedule:"
    echo "=========================="
    
    if crontab -l 2>/dev/null | grep -q "$dataset_script\|$replication_script"; then
        echo "Scheduled jobs found:"
        crontab -l 2>/dev/null | grep -A1 -B1 "$dataset_script\|$replication_script"
    else
        echo "No ZFS scripts currently scheduled"
        if [[ "$ENABLE_SCHEDULING" == "yes" ]]; then
            echo ""
            echo "Scheduling is enabled in config but not installed."
            echo "Run: source zfs-config.sh && setup_cron_jobs"
        fi
    fi
    
    echo ""
    echo "Current configuration:"
    echo "  ENABLE_SCHEDULING: $ENABLE_SCHEDULING"
    echo "  Dataset Converter: $DATASET_CONVERTER_SCHEDULE"
    echo "  Snapshot & Replication: $REPLICATION_SCHEDULE"
}

# Export all configuration variables and functions
export -f setup_passwordless_sudo validate_config setup_cron_jobs remove_cron_jobs show_cron_schedule
export GOTIFY_SERVER_URL GOTIFY_APP_TOKEN notification_type
export LOG_FILE LOG_MAX_SIZE LOG_MAX_FILES
export MOUNT_POINT DRY_RUN
export SHOULD_PROCESS_CONTAINERS SOURCE_POOL_APPDATA SOURCE_DATASET_APPDATA
export SHOULD_PROCESS_VMS SOURCE_POOL_VMS SOURCE_DATASET_VMS VM_FORCE_SHUTDOWN_WAIT
export SOURCE_DATASETS_ARRAY CLEANUP_TEMP_DIRS REPLACE_SPACES BUFFER_ZONE
export SOURCE_POOL SOURCE_DATASET SOURCE_DATASET_AUTO_SELECT 
export SOURCE_DATASET_AUTO_SELECT_EXCLUDE_PREFIX SOURCE_DATASET_AUTO_SELECT_EXCLUDES
export AUTO_SNAPSHOTS SNAPSHOT_HOURS SNAPSHOT_DAYS SNAPSHOT_WEEKS SNAPSHOT_MONTHS SNAPSHOT_YEARS
export DESTINATION_REMOTE REMOTE_USER REMOTE_SERVER REPLICATION
export DESTINATION_POOL PARENT_DESTINATION_DATASET SYNCOID_MODE
export PARENT_DESTINATION_FOLDER RSYNC_TYPE
export SANOID_CONFIG_DIR SANOID_BINARY SYNCOID_BINARY
export ENABLE_SCHEDULING DATASET_CONVERTER_SCHEDULE REPLICATION_SCHEDULE
export stopped_containers stopped_vms converted_folders

# Auto-setup cron jobs if enabled and this script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-setup}" in
        "setup")
            echo "Setting up ZFS script scheduling..."
            setup_cron_jobs
            ;;
        "remove")
            echo "Removing ZFS script scheduling..."
            remove_cron_jobs
            ;;
        "show"|"status")
            show_cron_schedule
            ;;
        "help"|"-h"|"--help")
            echo "ZFS Config Scheduling Management"
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  setup    - Install cron jobs (default)"
            echo "  remove   - Remove cron jobs"
            echo "  show     - Show current schedule"
            echo "  help     - Show this help"
            echo ""
            echo "Before running setup, edit this file and set:"
            echo "  ENABLE_SCHEDULING=\"yes\""
            echo "  Configure your desired schedules"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
fi
