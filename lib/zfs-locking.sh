#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   ZFS Locking Library                                                   # #
# #   Provides locking mechanisms to prevent race conditions               # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# This library provides locking functions to prevent race conditions in:
#   - Docker container operations
#   - VM operations
#   - Dataset operations
#
# Locking Strategy:
#   - Uses flock for file-based advisory locking
#   - Supports timeout-based lock acquisition
#   - Automatic cleanup on script exit
#   - Prevents deadlocks with timeout mechanism
#
# Security Note:
#   flock provides ADVISORY locking only — it coordinates cooperating
#   processes (e.g. multiple instances of these scripts). A non-cooperating
#   process or a determined attacker can bypass the lock entirely. Do NOT
#   rely on this for security-critical mutual exclusion; it is designed for
#   multi-agent coordination to prevent accidental concurrent operations.
#
# Functions provided:
#   - acquire_lock: Acquire a lock with timeout
#   - release_lock: Release a lock
#   - container_lock_acquire: Lock a specific container
#   - container_lock_release: Release container lock
#   - vm_lock_acquire: Lock a specific VM
#   - vm_lock_release: Release VM lock
#   - dataset_lock_acquire: Lock dataset operations
#   - dataset_lock_release: Release dataset lock
#   - cleanup_all_locks: Release all held locks

# Get the directory where this library is located
ZFS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
if [[ -f "$ZFS_LIB_DIR/zfs-error-handling.sh" ]]; then
    source "$ZFS_LIB_DIR/zfs-error-handling.sh"
fi

if [[ -f "$ZFS_LIB_DIR/zfs-common.sh" ]]; then
    source "$ZFS_LIB_DIR/zfs-common.sh"
fi

# Lock directory - stores lock files
ZFS_LOCK_DIR="${ZFS_LOCK_DIR:-/var/run/zfs-locks}"

# Track held locks for cleanup
declare -g -A ZFS_HELD_LOCKS=()

# Default lock timeout (seconds)
ZFS_LOCK_TIMEOUT="${ZFS_LOCK_TIMEOUT:-30}"

#######################################
# Initialize lock directory
# Creates the lock directory with secure permissions
# Globals:
#   ZFS_LOCK_DIR
# Returns:
#   0 on success, 1 on error
#######################################
init_lock_dir() {
    if [[ ! -d "$ZFS_LOCK_DIR" ]]; then
        if mkdir -p "$ZFS_LOCK_DIR" 2>/dev/null; then
            chmod 755 "$ZFS_LOCK_DIR"
            if declare -F log_message >/dev/null 2>&1; then
                log_message "INFO" "Created lock directory: $ZFS_LOCK_DIR"
            fi
        else
            if declare -F error >/dev/null 2>&1; then
                error "Failed to create lock directory: $ZFS_LOCK_DIR"
            else
                echo "ERROR: Failed to create lock directory: $ZFS_LOCK_DIR" >&2
            fi
            return 1
        fi
    fi
    return 0
}

#######################################
# Acquire a lock with timeout
# Uses flock for advisory locking
# Arguments:
#   $1 - Lock file path
#   $2 - Timeout in seconds (optional, default: ZFS_LOCK_TIMEOUT)
#   $3 - Lock description (for logging)
# Returns:
#   0 on success (lock acquired), 1 on timeout/failure
# Outputs:
#   File descriptor number on success
#######################################
acquire_lock() {
    local lock_file="$1"
    local timeout="${2:-$ZFS_LOCK_TIMEOUT}"
    local description="${3:-$lock_file}"

    # Initialize lock directory
    if ! init_lock_dir; then
        return 1
    fi

    # Validate lock file path
    if [[ -z "$lock_file" ]]; then
        if declare -F error >/dev/null 2>&1; then
            error "acquire_lock: lock_file cannot be empty"
        fi
        return 1
    fi

    # Ensure lock file exists
    if [[ ! -f "$lock_file" ]]; then
        touch "$lock_file" 2>/dev/null || {
            if declare -F error >/dev/null 2>&1; then
                error "Failed to create lock file: $lock_file"
            fi
            return 1
        }
    fi

    # Allocate an available file descriptor automatically (Bash 4.1+)
    local fd
    if ! exec {fd}> "$lock_file" 2>/dev/null; then
        if declare -F error >/dev/null 2>&1; then
            error "Failed to open file descriptor for lock: $lock_file"
        fi
        return 1
    fi

    # Try to acquire lock with timeout
    if declare -F log_message >/dev/null 2>&1; then
        log_message "INFO" "Acquiring lock: $description (timeout: ${timeout}s)"
    fi

    local start_time
    start_time=$(date +%s)
    while true; do
        # Try non-blocking lock
        if flock -n "$fd" 2>/dev/null; then
            # Lock acquired
            ZFS_HELD_LOCKS["$lock_file"]="$fd"
            if declare -F log_message >/dev/null 2>&1; then
                log_message "INFO" "Lock acquired: $description (fd: $fd)"
            fi
            echo "$fd"
            return 0
        fi

        # Check timeout
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [[ $elapsed -ge $timeout ]]; then
            # Timeout - close fd and fail
            eval "exec $fd>&-"
            if declare -F error >/dev/null 2>&1; then
                error "Lock timeout after ${timeout}s: $description"
            fi
            return 1
        fi

        # Wait a bit before retry (with jitter to avoid thundering herd)
        sleep 0.$(( RANDOM % 10 + 5 ))
    done
}

#######################################
# Release a lock
# Arguments:
#   $1 - Lock file path
# Returns:
#   0 on success, 1 on error
#######################################
release_lock() {
    local lock_file="$1"

    if [[ -z "$lock_file" ]]; then
        if declare -F error >/dev/null 2>&1; then
            error "release_lock: lock_file cannot be empty"
        fi
        return 1
    fi

    # Check if we have this lock
    if [[ -z "${ZFS_HELD_LOCKS[$lock_file]:-}" ]]; then
        if declare -F log_message >/dev/null 2>&1; then
            log_message "WARNING" "Attempted to release lock not held: $lock_file"
        fi
        return 0
    fi

    local fd="${ZFS_HELD_LOCKS[$lock_file]}"

    # Release lock by closing file descriptor
    if eval "exec $fd>&-" 2>/dev/null; then
        unset "ZFS_HELD_LOCKS[$lock_file]"
        if declare -F log_message >/dev/null 2>&1; then
            log_message "INFO" "Released lock: $lock_file (fd: $fd)"
        fi
        return 0
    else
        if declare -F error >/dev/null 2>&1; then
            error "Failed to release lock: $lock_file"
        fi
        return 1
    fi
}

#######################################
# Acquire lock for a Docker container
# Prevents concurrent operations on the same container
# Arguments:
#   $1 - Container ID or name
#   $2 - Timeout in seconds (optional)
# Returns:
#   0 on success (lock acquired), 1 on failure
# Outputs:
#   Lock file path on success
#######################################
container_lock_acquire() {
    local container="$1"
    local timeout="${2:-$ZFS_LOCK_TIMEOUT}"

    if [[ -z "$container" ]]; then
        if declare -F error >/dev/null 2>&1; then
            error "container_lock_acquire: container ID/name required"
        fi
        return 1
    fi

    # Sanitize container name for filename
    local safe_name
    safe_name=$(echo "$container" | tr -c '[:alnum:]_-' '_')

    local lock_file="$ZFS_LOCK_DIR/container-${safe_name}.lock"

    if acquire_lock "$lock_file" "$timeout" "container:$container"; then
        echo "$lock_file"
        return 0
    else
        return 1
    fi
}

#######################################
# Release lock for a Docker container
# Arguments:
#   $1 - Container ID or name
# Returns:
#   0 on success, 1 on error
#######################################
container_lock_release() {
    local container="$1"

    if [[ -z "$container" ]]; then
        if declare -F error >/dev/null 2>&1; then
            error "container_lock_release: container ID/name required"
        fi
        return 1
    fi

    # Sanitize container name for filename
    local safe_name
    safe_name=$(echo "$container" | tr -c '[:alnum:]_-' '_')

    local lock_file="$ZFS_LOCK_DIR/container-${safe_name}.lock"

    release_lock "$lock_file"
}

#######################################
# Execute function with container locked
# Automatically acquires and releases lock
# Arguments:
#   $1 - Container ID or name
#   $2 - Timeout in seconds
#   $3+ - Command to execute
# Returns:
#   Command exit code
#######################################
with_container_lock() {
    local container="$1"
    local timeout="$2"
    shift 2
    local cmd=("$@")

    local lock_file
    if ! lock_file=$(container_lock_acquire "$container" "$timeout"); then
        if declare -F error >/dev/null 2>&1; then
            error "Failed to acquire container lock: $container"
        fi
        return 1
    fi

    # Execute command
    local exit_code=0
    "${cmd[@]}" || exit_code=$?

    # Release lock
    container_lock_release "$container"

    return $exit_code
}

#######################################
# Acquire lock for a VM
# Prevents concurrent operations on the same VM
# Arguments:
#   $1 - VM name
#   $2 - Timeout in seconds (optional)
# Returns:
#   0 on success (lock acquired), 1 on failure
# Outputs:
#   Lock file path on success
#######################################
vm_lock_acquire() {
    local vm_name="$1"
    local timeout="${2:-$ZFS_LOCK_TIMEOUT}"

    if [[ -z "$vm_name" ]]; then
        if declare -F error >/dev/null 2>&1; then
            error "vm_lock_acquire: VM name required"
        fi
        return 1
    fi

    # Sanitize VM name for filename
    local safe_name
    safe_name=$(echo "$vm_name" | tr -c '[:alnum:]_-' '_')

    local lock_file="$ZFS_LOCK_DIR/vm-${safe_name}.lock"

    if acquire_lock "$lock_file" "$timeout" "vm:$vm_name"; then
        echo "$lock_file"
        return 0
    else
        return 1
    fi
}

#######################################
# Release lock for a VM
# Arguments:
#   $1 - VM name
# Returns:
#   0 on success, 1 on error
#######################################
vm_lock_release() {
    local vm_name="$1"

    if [[ -z "$vm_name" ]]; then
        if declare -F error >/dev/null 2>&1; then
            error "vm_lock_release: VM name required"
        fi
        return 1
    fi

    # Sanitize VM name for filename
    local safe_name
    safe_name=$(echo "$vm_name" | tr -c '[:alnum:]_-' '_')

    local lock_file="$ZFS_LOCK_DIR/vm-${safe_name}.lock"

    release_lock "$lock_file"
}

#######################################
# Execute function with VM locked
# Automatically acquires and releases lock
# Arguments:
#   $1 - VM name
#   $2 - Timeout in seconds
#   $3+ - Command to execute
# Returns:
#   Command exit code
#######################################
with_vm_lock() {
    local vm_name="$1"
    local timeout="$2"
    shift 2
    local cmd=("$@")

    local lock_file
    if ! lock_file=$(vm_lock_acquire "$vm_name" "$timeout"); then
        if declare -F error >/dev/null 2>&1; then
            error "Failed to acquire VM lock: $vm_name"
        fi
        return 1
    fi

    # Execute command
    local exit_code=0
    "${cmd[@]}" || exit_code=$?

    # Release lock
    vm_lock_release "$vm_name"

    return $exit_code
}

#######################################
# Acquire lock for dataset operations
# Prevents concurrent dataset creation/modification
# Arguments:
#   $1 - Dataset name or path
#   $2 - Timeout in seconds (optional)
# Returns:
#   0 on success (lock acquired), 1 on failure
# Outputs:
#   Lock file path on success
#######################################
dataset_lock_acquire() {
    local dataset="$1"
    local timeout="${2:-$ZFS_LOCK_TIMEOUT}"

    if [[ -z "$dataset" ]]; then
        if declare -F error >/dev/null 2>&1; then
            error "dataset_lock_acquire: dataset name required"
        fi
        return 1
    fi

    # Sanitize dataset name for filename (replace / with -)
    local safe_name
    safe_name=$(echo "$dataset" | tr '/' '-' | tr -c '[:alnum:]_-' '_')

    local lock_file="$ZFS_LOCK_DIR/dataset-${safe_name}.lock"

    if acquire_lock "$lock_file" "$timeout" "dataset:$dataset"; then
        echo "$lock_file"
        return 0
    else
        return 1
    fi
}

#######################################
# Release lock for a dataset
# Arguments:
#   $1 - Dataset name or path
# Returns:
#   0 on success, 1 on error
#######################################
dataset_lock_release() {
    local dataset="$1"

    if [[ -z "$dataset" ]]; then
        if declare -F error >/dev/null 2>&1; then
            error "dataset_lock_release: dataset name required"
        fi
        return 1
    fi

    # Sanitize dataset name for filename
    local safe_name
    safe_name=$(echo "$dataset" | tr '/' '-' | tr -c '[:alnum:]_-' '_')

    local lock_file="$ZFS_LOCK_DIR/dataset-${safe_name}.lock"

    release_lock "$lock_file"
}

#######################################
# Execute function with dataset locked
# Automatically acquires and releases lock
# Arguments:
#   $1 - Dataset name
#   $2 - Timeout in seconds
#   $3+ - Command to execute
# Returns:
#   Command exit code
#######################################
with_dataset_lock() {
    local dataset="$1"
    local timeout="$2"
    shift 2
    local cmd=("$@")

    local lock_file
    if ! lock_file=$(dataset_lock_acquire "$dataset" "$timeout"); then
        if declare -F error >/dev/null 2>&1; then
            error "Failed to acquire dataset lock: $dataset"
        fi
        return 1
    fi

    # Execute command
    local exit_code=0
    "${cmd[@]}" || exit_code=$?

    # Release lock
    dataset_lock_release "$dataset"

    return $exit_code
}

#######################################
# Cleanup all held locks
# Should be called on script exit
# Globals:
#   ZFS_HELD_LOCKS
# Returns:
#   0 always
#######################################
cleanup_all_locks() {
    if [[ ${#ZFS_HELD_LOCKS[@]} -gt 0 ]]; then
        if declare -F log_message >/dev/null 2>&1; then
            log_message "INFO" "Cleaning up ${#ZFS_HELD_LOCKS[@]} held locks"
        fi

        for lock_file in "${!ZFS_HELD_LOCKS[@]}"; do
            release_lock "$lock_file"
        done
    fi

    return 0
}

# Set up automatic cleanup on exit
trap cleanup_all_locks EXIT INT TERM

# Export locking functions
export -f init_lock_dir
export -f acquire_lock
export -f release_lock
export -f container_lock_acquire
export -f container_lock_release
export -f with_container_lock
export -f vm_lock_acquire
export -f vm_lock_release
export -f with_vm_lock
export -f dataset_lock_acquire
export -f dataset_lock_release
export -f with_dataset_lock
export -f cleanup_all_locks
