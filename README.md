# ZFS Management Scripts for Ubuntu

A comprehensive set of Ubuntu-compatible ZFS management scripts with Gotify notifications, automatic logging, and scheduling capabilities. These scripts automate ZFS dataset creation and provide robust snapshot and replication functionality.

## 🚀 Features

- **Auto Dataset Conversion**: Automatically converts regular directories to ZFS datasets
- **Snapshot Management**: Automated snapshot creation and retention using Sanoid
- **Flexible Replication**: Support for both ZFS (syncoid) and rsync replication methods
- **Smart Service Management**: Safely stops and restarts Docker containers and VMs during operations
- **Gotify Notifications**: Real-time notifications for success/failure events
- **Comprehensive Logging**: Automatic log rotation and detailed operation logs
- **Automated Scheduling**: Built-in cron job management
- **Safety Features**: Dry-run mode, space validation, data verification
- **Remote Support**: Full support for remote server replication via SSH

## 📋 Table of Contents

- [Quick Start](#-quick-start)
- [Installation](#-installation)
- [Configuration](#-configuration)
- [Usage](#-usage)
- [Scheduling](#-scheduling)
- [Scripts Overview](#-scripts-overview)
- [Advanced Configuration](#-advanced-configuration)
- [Troubleshooting](#-troubleshooting)

## ⚡ Quick Start

1. **Install dependencies and configure:**
   ```bash
   # Install required packages
   sudo apt update
   sudo apt install zfsutils-linux sanoid docker.io
   
   # Clone or download the scripts
   git clone <repository-url>
   cd zfs-scripts
   
   # Make scripts executable
   chmod +x *.sh
   ```

2. **Configure your settings:**
   ```bash
   # Edit the main configuration file
   nano zfs-config.sh
   
   # At minimum, configure:
   # - SOURCE_POOL (your ZFS pool name)
   # - GOTIFY_SERVER_URL and GOTIFY_APP_TOKEN (for notifications)
   # - LOG_FILE path (ensure directory exists and is writable)
   ```

3. **Test the configuration:**
   ```bash
   # Set DRY_RUN="yes" in zfs-config.sh, then test
   sudo ./zfs-auto-datasets-ubuntu.sh
   sudo ./zfs-replications-ubuntu.sh
   ```

4. **Setup automated scheduling:**
   ```bash
   # Enable scheduling in zfs-config.sh
   # Set ENABLE_SCHEDULING="yes"
   
   # Install cron jobs
   ./zfs-config.sh setup
   ```

## 🔧 Installation

### Prerequisites

```bash
# Update package list
sudo apt update

# Install ZFS utilities (required)
sudo apt install zfsutils-linux

# Install Sanoid for snapshot management (required for snapshots)
sudo apt install sanoid

# Install Docker (optional - only if processing containers)
sudo apt install docker.io
sudo systemctl enable docker
sudo systemctl start docker

# Install libvirt (optional - only if processing VMs)
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients

# Install curl for Gotify notifications (usually pre-installed)
sudo apt install curl
```

### Gotify Server Setup

1. **Install Gotify server** (if not already running):
   ```bash
   # Using Docker (recommended)
   docker run -d --name gotify \
     -p 8080:80 \
     -v /var/lib/gotify:/app/data \
     gotify/server
   ```

2. **Create application in Gotify:**
   - Open Gotify web interface (http://your-server:8080)
   - Login with default credentials (admin/admin)
   - Go to "Apps" section
   - Create new application named "ZFS Scripts"
   - Copy the generated token

### File Setup

1. **Download scripts:**
   ```bash
   # Create directory for scripts
   sudo mkdir -p /opt/zfs-scripts
   cd /opt/zfs-scripts
   
   # Copy the three main files:
   # - zfs-config.sh
   # - zfs-auto-datasets-ubuntu.sh  
   # - zfs-replications-ubuntu.sh
   ```

2. **Set permissions:**
   ```bash
   sudo chmod +x *.sh
   sudo chown root:root *.sh
   ```

3. **Create log directory:**
   ```bash
   sudo mkdir -p /var/log
   sudo touch /var/log/zfs-scripts.log
   sudo chmod 640 /var/log/zfs-scripts.log
   ```

## ⚙️ Configuration

### Main Configuration File: `zfs-config.sh`

This file contains all settings for both scripts. Key sections:

#### Core ZFS Settings
```bash
MOUNT_POINT="/mnt"              # Base mount point for ZFS datasets
SOURCE_POOL="tank"              # Your primary ZFS pool name
SOURCE_DATASET="data"           # Primary dataset name
DRY_RUN="no"                   # Set to "yes" for testing
```

#### Auto Dataset Converter Settings
```bash
# Docker container processing
SHOULD_PROCESS_CONTAINERS="yes"    # Enable Docker appdata conversion
SOURCE_POOL_APPDATA="tank"         # Pool containing Docker appdata
SOURCE_DATASET_APPDATA="appdata"   # Dataset name for Docker appdata

# Virtual machine processing
SHOULD_PROCESS_VMS="yes"           # Enable VM vdisk conversion
SOURCE_POOL_VMS="tank"             # Pool containing VM domains
SOURCE_DATASET_VMS="domains"       # Dataset name for VM domains

# Additional datasets to process
SOURCE_DATASETS_ARRAY=(
    "tank/media"
    "tank/documents"
)
```

#### Snapshot & Replication Settings
```bash
# Snapshot configuration
AUTO_SNAPSHOTS="yes"          # Enable automatic snapshots
SNAPSHOT_DAYS="7"             # Keep 7 daily snapshots
SNAPSHOT_WEEKS="4"            # Keep 4 weekly snapshots
SNAPSHOT_MONTHS="3"           # Keep 3 monthly snapshots

# Replication method
REPLICATION="zfs"             # Options: "zfs", "rsync", "none"

# ZFS replication (if REPLICATION="zfs")
DESTINATION_POOL="backup"     # Destination pool
PARENT_DESTINATION_DATASET="replicas"  # Parent dataset for replicas

# Remote replication
DESTINATION_REMOTE="no"       # Set to "yes" for remote replication
REMOTE_USER="root"            # Remote server username
REMOTE_SERVER="192.168.1.100" # Remote server address
```

#### Notification & Logging
```bash
# Gotify configuration
GOTIFY_SERVER_URL="http://localhost:8080"
GOTIFY_APP_TOKEN="your-app-token-here"
notification_type="all"       # Options: "all", "error", "none"

# Logging configuration
LOG_FILE="/var/log/zfs-scripts.log"
LOG_MAX_SIZE="10M"            # Rotate when log exceeds this size
LOG_MAX_FILES=5               # Keep this many rotated log files
```

#### Scheduling Settings
```bash
ENABLE_SCHEDULING="yes"                    # Enable automatic cron setup
DATASET_CONVERTER_SCHEDULE="0 2 * * *"    # Daily at 2 AM
REPLICATION_SCHEDULE="0 3 * * *"           # Daily at 3 AM
```

## 🎯 Usage

### Manual Execution

1. **Test with dry-run mode:**
   ```bash
   # Set DRY_RUN="yes" in zfs-config.sh
   sudo ./zfs-auto-datasets-ubuntu.sh
   sudo ./zfs-replications-ubuntu.sh
   ```

2. **Run for real:**
   ```bash
   # Set DRY_RUN="no" in zfs-config.sh
   sudo ./zfs-auto-datasets-ubuntu.sh
   sudo ./zfs-replications-ubuntu.sh
   ```

3. **Monitor logs:**
   ```bash
   # View real-time logs
   tail -f /var/log/zfs-scripts.log
   
   # View recent entries
   tail -100 /var/log/zfs-scripts.log
   
   # Search for errors
   grep ERROR /var/log/zfs-scripts.log
   ```

### Script-Specific Usage

#### Auto Dataset Converter (`zfs-auto-datasets-ubuntu.sh`)

**Purpose**: Converts regular directories to ZFS datasets
**When to use**: 
- After creating new Docker containers (appdata folders)
- After creating new VMs (vdisk folders)  
- When you want any regular directory to become a ZFS dataset

**What it does**:
1. Scans configured datasets for regular directories
2. Safely stops Docker containers/VMs using those directories
3. Renames directories to `_temp` suffix
4. Creates new ZFS datasets
5. Copies data using rsync with validation
6. Cleans up temporary directories
7. Restarts stopped services

#### Snapshot & Replication (`zfs-replications-ubuntu.sh`)

**Purpose**: Creates snapshots and replicates data
**When to use**:
- Regular backups (daily/weekly)
- Before system changes
- For disaster recovery setup

**What it does**:
1. Creates snapshots using Sanoid (configurable retention)
2. Prunes old snapshots based on retention policy
3. Replicates data using ZFS (syncoid) or rsync
4. Supports both local and remote destinations
5. Handles multiple datasets automatically

## 📅 Scheduling

The configuration file includes built-in cron job management:

### Setup Automatic Scheduling

1. **Configure schedules in `zfs-config.sh`:**
   ```bash
   ENABLE_SCHEDULING="yes"
   DATASET_CONVERTER_SCHEDULE="0 2 * * *"    # Daily at 2 AM
   REPLICATION_SCHEDULE="0 3 * * *"          # Daily at 3 AM (after conversion)
   ```

2. **Install cron jobs:**
   ```bash
   ./zfs-config.sh setup
   ```

3. **Verify installation:**
   ```bash
   ./zfs-config.sh show
   crontab -l
   ```

### Schedule Management Commands

```bash
# Install/update cron jobs
./zfs-config.sh setup

# Remove cron jobs
./zfs-config.sh remove

# Show current schedule
./zfs-config.sh show

# Get help
./zfs-config.sh help
```

### Cron Schedule Examples

```bash
# Every 6 hours
"0 */6 * * *"

# Daily at 2:30 AM
"30 2 * * *"

# Weekly on Sunday at 3 AM
"0 3 * * 0"

# Monthly on the 1st at 4 AM
"0 4 1 * *"

# Weekdays only at 1 AM
"0 1 * * 1-5"
```

## 📖 Scripts Overview

### `zfs-config.sh` - Central Configuration
- **Purpose**: Shared configuration file for both scripts
- **Features**: Configuration validation, cron job management
- **Usage**: Source this file or run directly for scheduling

### `zfs-auto-datasets-ubuntu.sh` - Dataset Converter
- **Purpose**: Converts directories to ZFS datasets
- **Key Features**:
  - Docker container management
  - VM management with graceful shutdown
  - Space validation before conversion
  - Data integrity verification
  - German umlaut normalization
  - Comprehensive error handling

### `zfs-replications-ubuntu.sh` - Snapshot & Replication
- **Purpose**: Automated snapshots and data replication
- **Key Features**:
  - Sanoid integration for snapshots
  - Multiple replication methods (ZFS/rsync)
  - Remote server support
  - Auto-dataset selection with exclusions
  - Incremental and mirror rsync modes
  - Comprehensive error handling

## 🔧 Advanced Configuration

### Multiple Pool Configuration

```bash
# Configure multiple source datasets
SOURCE_DATASETS_ARRAY=(
    "pool1/data"
    "pool1/media"
    "pool2/documents"
    "pool2/backups"
)
```

### Remote Replication Setup

1. **Setup SSH key authentication:**
   ```bash
   # Generate SSH key (if not exists)
   ssh-keygen -t rsa -b 4096
   
   # Copy to remote server
   ssh-copy-id user@remote-server
   
   # Test connection
   ssh user@remote-server echo "Connection successful"
   ```

2. **Configure remote settings:**
   ```bash
   DESTINATION_REMOTE="yes"
   REMOTE_USER="backup"
   REMOTE_SERVER="backup.example.com"
   ```

### Custom Sanoid Configuration

The scripts automatically generate Sanoid configs, but you can customize:

```bash
# Custom retention policies
SNAPSHOT_HOURS="24"    # Keep 24 hourly snapshots
SNAPSHOT_DAYS="30"     # Keep 30 daily snapshots
SNAPSHOT_WEEKS="8"     # Keep 8 weekly snapshots
SNAPSHOT_MONTHS="12"   # Keep 12 monthly snapshots
SNAPSHOT_YEARS="5"     # Keep 5 yearly snapshots
```

### Notification Customization

```bash
# Notification levels
notification_type="all"     # All notifications
notification_type="error"   # Only errors
notification_type="none"    # No notifications

# Custom Gotify server
GOTIFY_SERVER_URL="https://notify.example.com"
GOTIFY_APP_TOKEN="your-secure-token"
```

## 🐛 Troubleshooting

### Common Issues

#### 1. Permission Errors
```bash
# Ensure scripts are executable
chmod +x *.sh

# Run with sudo for ZFS operations
sudo ./script-name.sh

# Check log file permissions
ls -la /var/log/zfs-scripts.log
```

#### 2. ZFS Command Not Found
```bash
# Install ZFS utilities
sudo apt install zfsutils-linux

# Verify installation
which zfs
zfs version
```

#### 3. Sanoid/Syncoid Not Found
```bash
# Install sanoid package
sudo apt install sanoid

# Verify installation
which sanoid
which syncoid

# Update paths in zfs-config.sh if needed
SANOID_BINARY="/usr/sbin/sanoid"
SYNCOID_BINARY="/usr/sbin/syncoid"
```

#### 4. Docker/libvirt Issues
```bash
# Check Docker status
sudo systemctl status docker

# Check libvirt status
sudo systemctl status libvirtd

# Add user to docker group (logout/login required)
sudo usermod -a -G docker $USER
```

#### 5. SSH Connection Issues
```bash
# Test SSH connection
ssh -o BatchMode=yes user@remote-server echo "test"

# Check SSH key setup
ssh-add -l
cat ~/.ssh/id_rsa.pub

# Debug SSH connection
ssh -v user@remote-server
```

### Log Analysis

```bash
# View recent errors
grep ERROR /var/log/zfs-scripts.log | tail -20

# View specific script logs
grep "Auto Dataset Converter" /var/log/zfs-scripts.log

# Monitor logs in real-time
tail -f /var/log/zfs-scripts.log | grep -E "(ERROR|SUCCESS|INFO)"

# Check log rotation
ls -la /var/log/zfs-scripts.log*
```

### Configuration Validation

```bash
# Test configuration
source zfs-config.sh
validate_config

# Test dry-run mode
# Set DRY_RUN="yes" in config, then:
sudo ./zfs-auto-datasets-ubuntu.sh
```

### Debug Mode

Enable detailed logging by uncommenting debug lines:
```bash
# Add to top of scripts for verbose output
set -x

# Or use bash debug mode
bash -x ./script-name.sh
```

## 📞 Support

### Getting Help

1. **Check logs first**: `/var/log/zfs-scripts.log`
2. **Test with dry-run**: Set `DRY_RUN="yes"`
3. **Validate configuration**: Run `validate_config`
4. **Check system status**: Verify ZFS, Docker, libvirt status

### Reporting Issues

When reporting issues, include:
- Operating system version
- ZFS version (`zfs version`)
- Error messages from logs
- Configuration file (sanitized)
- Steps to reproduce

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request

## 📚 Additional Resources

- [ZFS Documentation](https://openzfs.github.io/openzfs-docs/)
- [Sanoid Documentation](https://github.com/jimsalterjrs/sanoid)
- [Gotify Documentation](https://gotify.net/docs/)
- [Ubuntu ZFS Guide](https://ubuntu.com/tutorials/setup-zfs-storage-pool)

---

**Made with ❤️ for the ZFS community**

*Adapted from SpaceInvaderOne's original Unraid scripts*