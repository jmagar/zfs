# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a collection of ZFS management scripts with two versions:

1. **Original Unraid Scripts** - For Unraid servers (version 6.12+)
2. **Ubuntu-Compatible Scripts** - For Ubuntu systems with ZFS support

The repository contains two main functional areas:
- **Auto Dataset Conversion** - Scripts that automatically convert regular directories to ZFS datasets
- **Snapshot & Replication** - Scripts for automated ZFS dataset snapshotting and replication

## Architecture

### Ubuntu Scripts (Current/Recommended)
- **Configuration**: `zfs-config.sh` - Shared configuration file for both scripts
- **Auto Dataset Converter**: `zfs-auto-datasets-ubuntu.sh` - Converts directories to ZFS datasets
- **Snapshot & Replication**: `zfs-replications-ubuntu.sh` - Handles snapshotting and replication
- **Features**: Gotify notifications, file logging with rotation, Ubuntu-compatible paths

### Original Unraid Scripts (Legacy)
- **Auto Dataset Converter**: `zfs-auto-datasets.sh` - Original Unraid version
- **Snapshot Replication**: `zfs-dataset-replications.sh` - Original Unraid version
- **Features**: Unraid GUI notifications, audio alerts, Unraid-specific paths

## Key Functional Components

### Auto Dataset Converter Features:
- Intelligently stops Docker containers/VMs whose data isn't already on ZFS datasets
- Converts directories to ZFS datasets while preserving data
- Supports multiple dataset sources via configurable array
- Safety checks for space availability and source validation
- Handles German umlauts normalization in dataset names
- Comprehensive logging and Gotify notifications

### Snapshot Replication Features:
- Integration with Sanoid for snapshot management
- Support for both local and remote replication
- ZFS-to-ZFS replication via syncoid
- Fallback rsync replication for non-ZFS destinations
- Configurable retention policies
- Auto-selection of datasets with exclusion rules
- Gotify notifications and file logging

## Ubuntu Setup & Dependencies

### Required Packages
```bash
# Install ZFS utilities
sudo apt update
sudo apt install zfsutils-linux

# Install Docker (if using container processing)
sudo apt install docker.io
sudo systemctl enable docker
sudo systemctl start docker

# Install libvirt (if using VM processing)
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients

# Install Sanoid/Syncoid (for snapshot management)
sudo apt install sanoid
```

### Gotify Setup
1. Install and configure Gotify server
2. Create application in Gotify UI to get app token
3. Configure `GOTIFY_SERVER_URL` and `GOTIFY_APP_TOKEN` in `zfs-config.sh`

### Configuration
1. Edit `zfs-config.sh` with your specific settings:
   - ZFS pool and dataset names
   - Mount points (typically `/mnt` on Ubuntu)
   - Gotify server details
   - Snapshot retention policies
2. Ensure log directory exists and is writable
3. Test with `DRY_RUN="yes"` before actual execution

## Script Usage Patterns

### Ubuntu Scripts
- **Configuration**: All settings in shared `zfs-config.sh` file
- **Execution**: Run directly via bash or cron
- **Testing**: Set `DRY_RUN="yes"` in config file
- **Monitoring**: Check logs at configured `LOG_FILE` path
- **Notifications**: Gotify messages for success/failure events

### Original Unraid Scripts  
- **Configuration**: Variables at the top of each script
- **Execution**: Via Unraid's User Scripts plugin
- **Testing**: Set `dry_run="yes"` in script variables
- **Monitoring**: Unraid GUI notifications and system logs

## Common Commands

### Ubuntu Scripts
```bash
# Test configuration
./zfs-auto-datasets-ubuntu.sh     # (with DRY_RUN="yes" in config)
./zfs-replications-ubuntu.sh      # (with DRY_RUN="yes" in config)

# Execute scripts
sudo ./zfs-auto-datasets-ubuntu.sh
sudo ./zfs-replications-ubuntu.sh

# View logs
tail -f /var/log/zfs-scripts.log

# Schedule with cron
sudo crontab -e
# Add lines like:
# 0 2 * * * /path/to/zfs-auto-datasets-ubuntu.sh
# 0 3 * * * /path/to/zfs-replications-ubuntu.sh
```

### Original Unraid Scripts
- **Test script behavior**: Set `dry_run="yes"` in the script variables before execution
- **Execute scripts**: Run via Unraid User Scripts plugin interface
- **Schedule execution**: Configure scheduling through User Scripts plugin
- **Monitor progress**: Use "Run in Background" for large operations and view logs

## Key Configuration Variables (Ubuntu Scripts)

All configuration is centralized in `zfs-config.sh`:

### Core ZFS Settings
- `MOUNT_POINT="/mnt"` - Base mount point for ZFS datasets
- `SOURCE_POOL="tank"` - Primary ZFS pool name
- `SOURCE_DATASET="data"` - Primary dataset name
- `DRY_RUN="no"` - Set to "yes" for testing

### Auto Dataset Converter Settings
- `SHOULD_PROCESS_CONTAINERS="no"` - Enable Docker appdata processing
- `SHOULD_PROCESS_VMS="no"` - Enable VM vdisk processing
- `SOURCE_DATASETS_ARRAY=()` - Additional datasets to process
- `CLEANUP_TEMP_DIRS="yes"` - Remove temporary data after conversion

### Snapshot & Replication Settings
- `AUTO_SNAPSHOTS="yes"` - Enable automatic snapshots
- `REPLICATION="zfs"` - Replication method (zfs/rsync/none)
- `DESTINATION_REMOTE="no"` - Enable remote replication
- Retention policy: `SNAPSHOT_DAYS`, `SNAPSHOT_WEEKS`, etc.

### Notification & Logging
- `GOTIFY_SERVER_URL` - Your Gotify server URL
- `GOTIFY_APP_TOKEN` - Gotify application token
- `LOG_FILE="/var/log/zfs-scripts.log"` - Log file location
- `notification_type="all"` - Notification level (all/error/none)

## Script Workflow Understanding

### Auto Dataset Converter Process:
1. Sources shared configuration and validates settings
2. Rotates log file if needed
3. Validates sources and checks for conversion work
4. Stops relevant Docker containers/VMs (if configured)
5. Renames directories to "_temp" suffix
6. Creates new ZFS datasets
7. Copies data using rsync with validation
8. Cleans up temporary directories (if enabled)
9. Restarts stopped services
10. Sends completion notifications via Gotify

### Snapshot Replication Process:
1. Sources shared configuration and validates settings
2. Determines datasets to process (manual or auto-select)
3. Phase 1: Pre-run checks and Sanoid config creation
4. Phase 2: Creates snapshots using Sanoid (if enabled)  
5. Phase 3: Prunes old snapshots and performs replication
6. Replicates via syncoid (ZFS) or rsync to local/remote destinations
7. Sends notifications and logs all operations

## Safety Features

- **Dry-run mode**: Test all operations without making changes
- **Automatic log rotation**: Prevents runaway log files
- **Service management**: Safely stops/starts Docker containers and VMs
- **Space validation**: Checks available space before conversions
- **Data validation**: Verifies file count and size after rsync
- **Temporary file handling**: Preserves originals until validation succeeds
- **Configuration validation**: Checks all settings at startup
- **Comprehensive error handling**: Detailed logging and notifications
- **SSH connectivity testing**: Validates remote servers before operations