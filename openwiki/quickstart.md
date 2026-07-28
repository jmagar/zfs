---
type: repository-guide
title: ZFS Management Scripts - Quick Start
description: Comprehensive ZFS management scripts for Ubuntu and Unraid systems with automated dataset conversion, snapshot management, and replication capabilities
tags: [zfs, automation, backup, ubuntu, unraid]
---

# ZFS Management Scripts

This repository provides comprehensive ZFS management scripts for Ubuntu and Unraid systems, with automated dataset conversion, snapshot management, and replication capabilities.

## Overview

The repository contains two main functional areas:

1. **Auto Dataset Conversion** - Automatically converts regular directories to ZFS datasets while preserving data and ensuring safety
2. **Snapshot & Replication** - Manages ZFS snapshots via Sanoid and supports both ZFS-to-ZFS (syncoid) and rsync replication

The scripts support both Ubuntu and Unraid environments, with Ubuntu versions being the current recommended option featuring Gotify notifications, file logging with rotation, and modern paths.

## Key Features

- **Intelligent Service Management** - Safely stops Docker containers and VMs during operations, then restarts them
- **Transactional Operations** - Atomic dataset conversions with rollback capability on failure
- **Flexible Replication** - Support for local and remote replication via ZFS (syncoid) or rsync
- **Comprehensive Safety** - Space validation, data verification, dry-run mode, and race condition prevention
- **Real-time Notifications** - Gotify integration for success/failure events
- **Automated Scheduling** - Built-in cron job management for regular operations

## Documentation Sections

### [Scripts & Functionality](scripts/)

- **[Auto Dataset Converter](scripts/auto-datasets.md)** - Directory to ZFS dataset conversion with transactional safety
- **[Replication Manager](scripts/replication.md)** - Snapshot creation, retention, and multi-method replication

### [Architecture & Libraries](libraries/)

- **[Library Overview](libraries/overview.md)** - Shared libraries for common operations, validation, error handling, locking, and transaction management

### [Operations & Recovery](operations/)

- **[Recovery Procedures](operations/recovery.md)** - Transaction recovery, manual rollback, and disaster recovery procedures

### [Development & Testing](development/)

- **[Testing Strategy](development/testing.md)** - BATS test framework, CI/CD pipeline, and test execution
- **[Code Quality](development/code-quality.md)** - Security considerations, best practices, and code review findings

## Quick Setup

### Prerequisites

```bash
# Install required packages
sudo apt update
sudo apt install zfsutils-linux sanoid docker.io

# Optional: Install BATS for testing
sudo apt install bats
```

### Basic Configuration

1. Clone the repository and make scripts executable:
```bash
git clone <repository-url>
cd zfs-scripts
chmod +x *.sh
```

2. Edit `zfs-config.sh` to configure at minimum:
   - `SOURCE_POOL` - Your ZFS pool name
   - `GOTIFY_SERVER_URL` and `GOTIFY_APP_TOKEN` - For notifications
   - `LOG_FILE` - Log file path (ensure directory exists)

3. Test with dry-run mode:
```bash
# Set DRY_RUN="yes" in zfs-config.sh
sudo ./zfs-auto-datasets-ubuntu.sh
sudo ./zfs-replications-ubuntu.sh
```

4. Enable automated scheduling (optional):
```bash
# Set ENABLE_SCHEDULING="yes" in zfs-config.sh
./zfs-config.sh setup
```

## Repository Structure

```
├── zfs-auto-datasets-ubuntu.sh    # Ubuntu dataset converter
├── zfs-replications-ubuntu.sh      # Ubuntu replication manager
├── zfs-config.sh                  # Shared configuration
├── lib/                            # Shared libraries
│   ├── zfs-common.sh              # Common functions
│   ├── zfs-validation.sh          # Input validation
│   ├── zfs-error-handling.sh      # Error handling
│   ├── zfs-locking.sh             # Race condition prevention
│   └── zfs-transactions.sh        # Transaction management
├── tests/                          # BATS test suite
├── manual-recovery.sh              # Transaction recovery tool
└── .github/workflows/              # CI/CD pipelines
```

## Safety Features

The scripts implement multiple safety layers:

- **Transactional Operations** - Dataset conversions use transactions with automatic rollback
- **Race Condition Prevention** - File-based advisory locking prevents concurrent operations
- **Space Validation** - Checks available space with configurable buffer (default 11%)
- **Data Verification** - Validates data integrity after conversion
- **Service Safety** - Gracefully stops/starts Docker containers and VMs
- **Dry Run Mode** - Test configuration without making changes

## Key Concepts

### Transactions

Dataset conversions use a transaction system with states: INITIATED → RENAMED → DATASET_CREATED → RSYNC_STARTED → RSYNC_COMPLETE → VALIDATED → COMPLETED. Failed transactions can be rolled back automatically or manually via [recovery procedures](operations/recovery.md).

### Locking

The locking strategy uses `flock`-based advisory locks to prevent race conditions when multiple processes might access the same resources. See [libraries/overview.md](libraries/overview.md#locking) for details.

### Service Management

The auto-dataset converter intelligently manages Docker containers and VMs:
- Detects if containers/VMs have data on ZFS datasets
- Stops services before conversion, restarts after completion
- Respects existing ZFS dataset mounts

## Further Reading

- [AGENTS.md](/AGENTS.md) and [CLAUDE.md](/CLAUDE.md) - Agent-specific guidance
- [README.md](/README.md) - Detailed user documentation and examples
- [lib/README.md](/lib/README.md) - Library function reference
- [TESTING.md](/TESTING.md) - Testing documentation
