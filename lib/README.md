# ZFS Management Libraries

This directory contains shared libraries used by ZFS management scripts.

## Libraries

### zfs-locking.sh (Stream 6)
**Purpose:** Provides locking mechanisms to prevent race conditions

**Functions:**
- `container_lock_acquire()` / `container_lock_release()` - Docker container locking
- `vm_lock_acquire()` / `vm_lock_release()` - VM locking
- `dataset_lock_acquire()` / `dataset_lock_release()` - Dataset locking
- `with_container_lock()` / `with_vm_lock()` / `with_dataset_lock()` - Helper functions
- `acquire_lock()` / `release_lock()` - Low-level locking
- `cleanup_all_locks()` - Cleanup on exit

**Usage:**
```bash
source "$SCRIPT_DIR/lib/zfs-locking.sh"

# Acquire lock, perform operation, release lock
if lock_file=$(container_lock_acquire "$container_id" 10); then
    # Verify state after lock
    state=$(docker inspect --format '{{.State.Status}}' "$container_id")

    # Perform operation
    docker stop "$container_id"

    # Release lock
    container_lock_release "$container_id"
fi
```

**Documentation:** See `LOCKING_STRATEGY.md` for complete details

## Testing

Test file: `tests/test-race-conditions.bats`

Run tests with:
```bash
bats tests/test-race-conditions.bats
```
