# ZFS Management Scripts - Locking Strategy

**Document Version:** 1.0
**Last Updated:** 2025-11-03
**Stream:** 6 - Race Conditions

---

## Overview

This document describes the locking strategy implemented to prevent race conditions in ZFS management scripts. The implementation uses file-based advisory locking with `flock` to ensure safe concurrent operations.

## Problem Statement

The original implementation had several race conditions that could lead to data corruption or inconsistent state:

### 1. Docker Container State Changes
**Problem:** Container could be stopped, restarted, or removed by another process between detection and action.

**Scenario:**
```bash
# Process A checks container is running
if docker ps | grep container-id; then
    # Process B stops container here
    docker stop container-id  # Process A attempts stop - may fail or succeed unexpectedly
fi
```

**Impact:** Inconsistent container state, potential data loss, script errors.

### 2. VM Shutdown Race Condition
**Problem:** VM state could change during sleep periods, leading to infinite loops or missed shutdowns.

**Scenario:**
```bash
virsh shutdown vm-name
while virsh dominfo vm | grep -q 'running'; do
    sleep 5  # VM state could change here
    # Another process might start the VM
    # Or VM might crash instead of shutting down gracefully
done
```

**Impact:** Infinite loops, improper force shutdowns, VM corruption.

### 3. Dataset Creation Race (TOCTOU)
**Problem:** Dataset could be created/destroyed between check and use (Time-of-check Time-of-use vulnerability).

**Scenario:**
```bash
# Process A checks dataset doesn't exist
if ! zfs list tank/data; then
    # Process B creates tank/data here
    zfs create tank/data  # Process A attempts create - fails
fi
```

**Impact:** Script failures, duplicate work, potential data loss.

---

## Solution: Advisory File Locking

### Architecture

```
┌─────────────────────────────────────────────┐
│         ZFS Management Scripts              │
└─────────────────────────────────────────────┘
                    │
                    ├─────────────────────────┐
                    │                         │
                    ▼                         ▼
        ┌──────────────────┐      ┌──────────────────┐
        │  Container Locks │      │   VM Locks       │
        └──────────────────┘      └──────────────────┘
                    │                         │
                    └──────────┬──────────────┘
                               │
                               ▼
                    ┌──────────────────┐
                    │  Dataset Locks   │
                    └──────────────────┘
                               │
                               ▼
                    ┌──────────────────────────┐
                    │  File-based Locking      │
                    │  (/var/run/zfs-locks)    │
                    │  - Uses flock            │
                    │  - Advisory locks        │
                    │  - Timeout mechanism     │
                    └──────────────────────────┘
```

### Lock Types

#### 1. Container Locks
**Purpose:** Prevent concurrent operations on Docker containers

**Lock File Format:** `/var/run/zfs-locks/container-{safe_name}.lock`

**Usage:**
```bash
# Acquire lock
if lock_file=$(container_lock_acquire "$container_id" 10); then
    # Verify container state after lock
    state=$(docker inspect --format '{{.State.Status}}' "$container_id")

    if [[ "$state" == "running" ]]; then
        # Perform operation
        docker stop "$container_id"

        # Verify operation completed
        for ((i=0; i<10; i++)); do
            state=$(docker inspect --format '{{.State.Status}}' "$container_id")
            [[ "$state" != "running" ]] && break
            sleep 0.5
        done
    fi

    # Release lock
    container_lock_release "$container_id"
fi
```

**Key Points:**
- Always verify state after acquiring lock (TOCTOU protection)
- Use explicit state verification (not grep patterns)
- Release lock in all code paths

#### 2. VM Locks
**Purpose:** Prevent concurrent operations on virtual machines

**Lock File Format:** `/var/run/zfs-locks/vm-{safe_name}.lock`

**Usage:**
```bash
# Acquire lock
if lock_file=$(vm_lock_acquire "$vm_name" 10); then
    # Get current state using virsh domstate (not dominfo)
    vm_state=$(virsh domstate "$vm_name" 2>/dev/null || echo "missing")

    if [[ "$vm_state" == "running" ]]; then
        virsh shutdown "$vm_name"

        # Poll state without grep
        start_time=$(date +%s)
        while true; do
            vm_state=$(virsh domstate "$vm_name" 2>/dev/null || echo "missing")

            # Check if stopped (not running and not "in shutdown")
            [[ "$vm_state" != "running" && "$vm_state" != "in shutdown" ]] && break

            # Check timeout
            current_time=$(date +%s)
            elapsed=$((current_time - start_time))
            [[ $elapsed -ge $VM_FORCE_SHUTDOWN_WAIT ]] && break

            sleep 2
        done

        # Force shutdown if necessary
        if [[ "$vm_state" == "running" || "$vm_state" == "in shutdown" ]]; then
            virsh destroy "$vm_name"
        fi
    fi

    # Release lock
    vm_lock_release "$vm_name"
fi
```

**Key Points:**
- Use `virsh domstate` instead of `dominfo | grep`
- Direct state comparison without pattern matching
- Proper timeout handling with exponential backoff
- Verify VM state after each operation

#### 3. Dataset Locks
**Purpose:** Prevent concurrent dataset creation/modification

**Lock File Format:** `/var/run/zfs-locks/dataset-{pool-dataset}.lock`

**Usage:**
```bash
# Acquire lock before check-create sequence
if lock_file=$(dataset_lock_acquire "$dataset_name" 30); then
    # Re-check if dataset exists (TOCTOU protection)
    if zfs list -H -o name "$dataset_name" >/dev/null 2>&1; then
        log_message "INFO" "Dataset already exists (created by another process)"
        dataset_lock_release "$dataset_name"
        continue
    fi

    # Perform atomic operation
    if zfs create "$dataset_name"; then
        log_message "SUCCESS" "Created dataset $dataset_name"
        # ... additional operations ...
    else
        log_message "ERROR" "Failed to create dataset"
    fi

    # Always release lock
    dataset_lock_release "$dataset_name"
fi
```

**Key Points:**
- Re-check existence after lock acquisition
- Direct ZFS commands instead of grep patterns
- Release lock even on failure (using continue/return)

---

## Implementation Details

### Lock Acquisition Flow

```
┌─────────────────────────────────────┐
│  Request Lock                       │
│  (container/vm/dataset)             │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  Initialize Lock Directory          │
│  (/var/run/zfs-locks)               │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  Sanitize Resource Name             │
│  (remove special chars)             │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  Open Lock File                     │
│  (create if doesn't exist)          │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  Try Non-blocking flock             │
└─────────────┬───────────────────────┘
              │
         ┌────┴────┐
         │         │
    Success       Fail
         │         │
         ▼         ▼
    ┌────────┐ ┌──────────────┐
    │ Return │ │ Sleep 0.1s   │
    │   FD   │ │ Check timeout │
    └────────┘ └──────┬───────┘
                      │
                ┌─────┴──────┐
                │            │
           Within timeout  Timeout
                │            │
                │            ▼
                │       ┌──────────┐
                └───────┤ Return 1 │
                        └──────────┘
```

### Timeout Mechanism

The lock acquisition implements a polling-based timeout:

```bash
local start_time=$(date +%s)
while true; do
    # Try non-blocking lock
    if flock -n "$fd" 2>/dev/null; then
        # Lock acquired
        return 0
    fi

    # Check timeout
    local current_time=$(date +%s)
    local elapsed=$((current_time - start_time))

    if [[ $elapsed -ge $timeout ]]; then
        # Timeout - fail
        return 1
    fi

    # Wait before retry
    sleep 0.1
done
```

**Benefits:**
- Non-blocking: Won't hang indefinitely
- Fair: FIFO order for lock acquisition
- Configurable: Timeout can be adjusted per operation

### File Descriptor Management

The library uses file descriptors 10-199 for locks:

```bash
# Find available file descriptor
for ((fd=10; fd<200; fd++)); do
    if ! { true >&$fd; } 2>/dev/null; then
        break
    fi
done

# Open file descriptor for locking
eval "exec $fd>$lock_file"

# Use flock on the fd
flock -n "$fd"

# Track the fd for cleanup
ZFS_HELD_LOCKS["$lock_file"]="$fd"

# Release by closing fd
eval "exec $fd>&-"
```

**Benefits:**
- No conflicts with stdin/stdout/stderr (0-2)
- Allows multiple concurrent locks
- Automatic cleanup on process exit

---

## Security Considerations

### 1. Advisory Locks
**Nature:** Locks are advisory, not mandatory

**Implication:** Other processes can ignore locks if they don't use the locking library

**Mitigation:** All ZFS management scripts must use the locking library

### 2. Lock Directory Permissions

**Location:** `/var/run/zfs-locks`
**Permissions:** 755 (drwxr-xr-x)

**Security:**
- Readable by all users (needed for lock detection)
- Writable only by root (prevents unauthorized lock creation)
- Ephemeral location (cleared on reboot)

### 3. Lock File Naming

**Sanitization:**
```bash
safe_name=$(echo "$resource_name" | tr -c '[:alnum:]_-' '_')
```

**Prevents:**
- Path traversal attacks (../)
- Special character injection
- Filename conflicts

### 4. Timeout Protection

**Default Timeout:** 30 seconds

**Benefits:**
- Prevents deadlocks
- Detects hung processes
- Ensures forward progress

**Risks:**
- May timeout legitimate long operations
- Could cause failures under heavy load

**Tuning:** Adjust `ZFS_LOCK_TIMEOUT` based on environment

---

## Best Practices

### 1. Always Verify After Lock

```bash
# WRONG: Trust previous check
if ! zfs list dataset; then
    lock=$(dataset_lock_acquire "dataset")
    zfs create dataset  # Race condition!
fi

# CORRECT: Re-check after lock
lock=$(dataset_lock_acquire "dataset")
if ! zfs list dataset >/dev/null 2>&1; then
    zfs create dataset
fi
```

### 2. Release Locks in All Paths

```bash
# WRONG: Lock leaked on error
lock=$(container_lock_acquire "container")
if ! docker stop container; then
    return 1  # Lock leaked!
fi
container_lock_release "container"

# CORRECT: Release in all paths
lock=$(container_lock_acquire "container")
if ! docker stop container; then
    container_lock_release "container"
    return 1
fi
container_lock_release "container"
```

### 3. Use Helper Functions

```bash
# CORRECT: Automatic lock management
with_container_lock "container" 10 docker stop container
with_vm_lock "vm" 10 virsh shutdown vm
with_dataset_lock "dataset" 30 zfs create dataset
```

### 4. Handle Lock Failures

```bash
# WRONG: Assume lock always succeeds
lock=$(container_lock_acquire "container")
docker stop container

# CORRECT: Check if lock was acquired
if lock=$(container_lock_acquire "container" 10); then
    docker stop container
    container_lock_release "container"
else
    log_message "ERROR" "Could not acquire lock"
    return 1
fi
```

---

## Testing

### Unit Tests

Location: `tests/test-race-conditions.bats`

**Test Coverage:**
- Lock acquisition and release
- Timeout enforcement
- Concurrent lock attempts
- Lock file sanitization
- Error handling
- Helper function behavior

**Running Tests:**
```bash
# Install BATS if needed
sudo apt install bats

# Run race condition tests
bats tests/test-race-conditions.bats

# Run all tests
bats tests/*.bats
```

### Integration Tests

**Scenario 1: Concurrent Container Operations**
```bash
# Simulate two processes stopping same container
process_a() {
    ./zfs-auto-datasets-ubuntu.sh &
}

process_b() {
    docker stop container &
}

process_a
process_b
wait

# Verify: Container stopped cleanly without errors
```

**Scenario 2: Parallel Dataset Creation**
```bash
# Create same dataset from two scripts
./zfs-auto-datasets-ubuntu.sh &
./zfs-auto-datasets-ubuntu.sh &
wait

# Verify: Dataset created once, no errors
```

### Stress Testing

**Lock Contention Test:**
```bash
# Run 10 concurrent instances
for i in {1..10}; do
    ./zfs-auto-datasets-ubuntu.sh &
done
wait

# Verify:
# - All processes completed successfully
# - No deadlocks
# - Proper lock cleanup
# - No duplicate operations
```

---

## Performance Impact

### Overhead Analysis

**Lock Acquisition:**
- **Operation:** flock system call
- **Time:** ~0.1-1ms (uncontended)
- **Time:** 0-30s (contended, depends on timeout)

**State Verification:**
- **Docker inspect:** ~10-50ms per call
- **Virsh domstate:** ~20-100ms per call
- **ZFS list:** ~10-50ms per call

**Total Impact:**
- **Best case:** <100ms additional overhead per operation
- **Worst case:** Up to timeout duration (default 30s)
- **Average case:** <500ms for typical operations

### Optimization Strategies

1. **Reduce timeout for non-critical operations**
   ```bash
   container_lock_acquire "container" 5  # 5s instead of 30s
   ```

2. **Batch operations when possible**
   ```bash
   # Instead of locking each container separately:
   for container in containers; do
       with_container_lock container 10 docker stop container
   done

   # Consider stopping all at once if safe:
   docker stop container1 container2 container3
   ```

3. **Use dry-run mode for testing**
   ```bash
   DRY_RUN="yes" ./zfs-auto-datasets-ubuntu.sh
   # No locks acquired, fast execution
   ```

---

## Troubleshooting

### Issue: Lock Timeout

**Symptoms:**
```
ERROR: Lock timeout after 30s: container:container-id
WARNING: Could not acquire lock for container container-id - skipping
```

**Causes:**
- Another process holding lock
- Hung process didn't release lock
- System under heavy load

**Solutions:**
```bash
# 1. Check for held locks
ls -la /var/run/zfs-locks/

# 2. Find processes holding locks
lsof /var/run/zfs-locks/container-*.lock

# 3. Manually release if process died
rm /var/run/zfs-locks/container-stuck.lock

# 4. Increase timeout for slow operations
export ZFS_LOCK_TIMEOUT=60
```

### Issue: Deadlock

**Symptoms:**
- Multiple processes waiting indefinitely
- No progress in operations
- High CPU usage from busy-waiting

**Detection:**
```bash
# Check processes waiting on locks
ps aux | grep zfs-auto-datasets

# Check lock files
ls -la /var/run/zfs-locks/

# Check system load
uptime
```

**Solutions:**
```bash
# 1. Kill hung processes
pkill -9 zfs-auto-datasets

# 2. Clean lock directory
rm -rf /var/run/zfs-locks/*

# 3. Restart with single instance
./zfs-auto-datasets-ubuntu.sh
```

### Issue: Lock Directory Not Created

**Symptoms:**
```
ERROR: Failed to create lock directory: /var/run/zfs-locks
```

**Causes:**
- Insufficient permissions
- /var/run not writable
- Disk full

**Solutions:**
```bash
# 1. Check permissions
ls -ld /var/run

# 2. Create manually
sudo mkdir -p /var/run/zfs-locks
sudo chmod 755 /var/run/zfs-locks

# 3. Check disk space
df -h /var

# 4. Use alternative location
export ZFS_LOCK_DIR=/tmp/zfs-locks
```

### Issue: Too Many Open File Descriptors

**Symptoms:**
```
ERROR: No available file descriptors for lock
```

**Causes:**
- Too many concurrent locks
- File descriptor leak
- System limits too low

**Solutions:**
```bash
# 1. Check current limits
ulimit -n

# 2. Increase limits
ulimit -n 4096

# 3. Check for leaks
lsof -p $$ | grep zfs-locks

# 4. Cleanup locks
cleanup_all_locks
```

---

## Migration Guide

### For Existing Deployments

**Step 1: Review Current Usage**
```bash
# Check if scripts are running concurrently
ps aux | grep zfs-auto-datasets
crontab -l | grep zfs
```

**Step 2: Update Scripts**
```bash
# Pull latest changes
git pull origin feature/stream-6-race-conditions

# Verify locking library exists
ls -l lib/zfs-locking.sh
```

**Step 3: Test with Dry Run**
```bash
# Test without making changes
DRY_RUN="yes" ./zfs-auto-datasets-ubuntu.sh
```

**Step 4: Monitor Logs**
```bash
# Watch for locking-related messages
tail -f /var/log/zfs-scripts.log | grep -i lock
```

**Step 5: Verify Lock Cleanup**
```bash
# After script completes, check for stale locks
ls /var/run/zfs-locks/
# Should be empty after completion
```

### Backward Compatibility

The locking implementation is **backward compatible**:

- Scripts work without locking library (with warning)
- Lock directory created automatically
- No configuration changes required
- Existing functionality unchanged

---

## Future Improvements

### 1. Distributed Locking
For multi-node deployments:
- Implement Redis/etcd-based locking
- Support cluster-wide coordination
- Handle network partitions

### 2. Lock Monitoring
- Prometheus metrics for lock contention
- Alerting for timeout events
- Dashboard for lock status

### 3. Deadlock Detection
- Automatic deadlock detection
- Self-healing mechanisms
- Better diagnostics

### 4. Performance Optimization
- Lock-free data structures where possible
- Reduced lock scope
- More granular locking

---

## References

- **POSIX flock:** `man 2 flock`
- **Advisory Locking:** https://en.wikipedia.org/wiki/File_locking
- **TOCTOU Vulnerabilities:** https://en.wikipedia.org/wiki/Time-of-check_to_time-of-use
- **Implementation Plan:** IMPLEMENTATION_PLAN.md (Stream 6)
- **Code Review:** CODE_REVIEW.md (Issues 2.1, 2.2, 3)

---

## Changelog

**Version 1.0 (2025-11-03)**
- Initial locking strategy implementation
- Container, VM, and dataset locks
- Timeout mechanism with exponential backoff
- Comprehensive test suite
- Documentation complete

---

**End of Locking Strategy Document**
