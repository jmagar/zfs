#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   ZFS Transaction Management Library                                    # #
# #   Provides transaction state tracking and rollback for dataset ops     # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# This library provides transaction management for non-atomic ZFS operations.
# It tracks the state of dataset conversions to enable recovery from failures.
#
# Transaction States:
#   INITIATED    - Transaction started, no filesystem changes yet
#   RENAMED      - Original directory renamed to _temp
#   DATASET_CREATED - ZFS dataset created
#   RSYNC_STARTED - Data copy initiated
#   RSYNC_COMPLETE - Data copy finished
#   VALIDATED    - Data verified, ready for cleanup
#   COMPLETED    - Transaction successfully completed
#   FAILED       - Transaction failed (manual intervention may be needed)
#   ROLLEDBACK   - Transaction rolled back to original state
#
# Functions:
#   transaction_start        - Start a new transaction
#   transaction_update_state - Update transaction state
#   transaction_complete     - Mark transaction as completed
#   transaction_fail         - Mark transaction as failed
#   transaction_rollback     - Rollback a transaction
#   transaction_list_pending - List all pending transactions
#   transaction_recover_all  - Recover all pending transactions
#   transaction_cleanup      - Clean up completed transaction files
#   transaction_get_info     - Get transaction information

# State file directory
readonly TX_STATE_DIR="${TX_STATE_DIR:-/var/lib/zfs-scripts/transactions}"
readonly TX_LOCK_DIR="${TX_LOCK_DIR:-/var/run/zfs-scripts/locks}"

# Get the directory where this library is located
ZFS_TX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
if [[ -f "$ZFS_TX_LIB_DIR/zfs-common.sh" ]]; then
    source "$ZFS_TX_LIB_DIR/zfs-common.sh"
fi

if [[ -f "$ZFS_TX_LIB_DIR/zfs-validation.sh" ]]; then
    source "$ZFS_TX_LIB_DIR/zfs-validation.sh"
fi

if [[ -f "$ZFS_TX_LIB_DIR/zfs-error-handling.sh" ]]; then
    source "$ZFS_TX_LIB_DIR/zfs-error-handling.sh"
fi

# Initialize transaction directory
_tx_init() {
    if [[ ! -d "$TX_STATE_DIR" ]]; then
        mkdir -p "$TX_STATE_DIR" 2>/dev/null || {
            echo "ERROR: Failed to create transaction state directory: $TX_STATE_DIR" >&2
            return 1
        }
        chmod 700 "$TX_STATE_DIR"
    fi

    if [[ ! -d "$TX_LOCK_DIR" ]]; then
        mkdir -p "$TX_LOCK_DIR" 2>/dev/null || {
            echo "ERROR: Failed to create transaction lock directory: $TX_LOCK_DIR" >&2
            return 1
        }
        chmod 700 "$TX_LOCK_DIR"
    fi

    return 0
}

#######################################
# Generate unique transaction ID
# Outputs:
#   Transaction ID (timestamp-random)
# Returns:
#   0 on success
#######################################
_tx_generate_id() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local random=$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')
    echo "tx_${timestamp}_${random}"
}

#######################################
# Get state file path for transaction
# Arguments:
#   $1 - Transaction ID
# Outputs:
#   State file path
#######################################
_tx_get_state_file() {
    local tx_id="$1"
    echo "$TX_STATE_DIR/${tx_id}.json"
}

#######################################
# Get lock file path for transaction
# Arguments:
#   $1 - Transaction ID
# Outputs:
#   Lock file path
#######################################
_tx_get_lock_file() {
    local tx_id="$1"
    echo "$TX_LOCK_DIR/${tx_id}.lock"
}

#######################################
# Acquire lock for transaction
# Arguments:
#   $1 - Transaction ID
# Outputs:
#   File descriptor number on success
# Returns:
#   0 on success, 1 on failure
#######################################
_tx_acquire_lock() {
    local tx_id="$1"
    local lock_file=$(_tx_get_lock_file "$tx_id")
    local timeout=30

    # Create lock file if it doesn't exist
    touch "$lock_file" 2>/dev/null || {
        echo "ERROR: Cannot create lock file: $lock_file" >&2
        return 1
    }

    # Allocate file descriptor and acquire exclusive lock atomically
    local lock_fd
    if ! exec {lock_fd}> "$lock_file" 2>/dev/null; then
        echo "ERROR: Cannot open lock file: $lock_file" >&2
        return 1
    fi

    # Try to acquire exclusive lock with timeout
    if ! flock -x -w $timeout $lock_fd 2>/dev/null; then
        exec {lock_fd}>&-  # Close FD
        echo "ERROR: Failed to acquire lock for transaction $tx_id (timeout after ${timeout}s)" >&2
        return 1
    fi

    # Write PID to lock file for debugging
    echo "$$" >&$lock_fd

    # Store FD for later release (export to parent scope)
    echo "$lock_fd"
    return 0
}

#######################################
# Release lock for transaction
# Arguments:
#   $1 - Transaction ID
#   $2 - Lock file descriptor
# Returns:
#   0 on success
#######################################
_tx_release_lock() {
    local tx_id="$1"
    local lock_fd="$2"  # Now receives FD as second parameter
    local lock_file=$(_tx_get_lock_file "$tx_id")

    # Release flock and close FD
    if [[ -n "$lock_fd" && "$lock_fd" =~ ^[0-9]+$ ]]; then
        flock -u $lock_fd 2>/dev/null || true
        exec {lock_fd}>&- 2>/dev/null || true
    fi

    # Remove lock file
    rm -f "$lock_file" 2>/dev/null || true
}

#######################################
# Write transaction state atomically
# Arguments:
#   $1 - State file path
#   $2 - JSON content
# Returns:
#   0 on success, 1 on failure
#######################################
_tx_write_state_atomic() {
    local state_file="$1"
    local content="$2"
    local temp_file="${state_file}.tmp.$$"

    # Write to temp file
    if ! echo "$content" > "$temp_file" 2>/dev/null; then
        echo "ERROR: Failed to write transaction state to temp file" >&2
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi

    # Atomic rename
    if ! mv "$temp_file" "$state_file" 2>/dev/null; then
        echo "ERROR: Failed to atomically update transaction state" >&2
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi

    chmod 600 "$state_file"
    return 0
}

#######################################
# Start a new transaction
# Arguments:
#   $1 - Operation type (e.g., "convert")
#   $2 - Dataset name
#   $3 - Source path (full path)
#   $4 - Temp path (full path with _temp suffix)
# Outputs:
#   Transaction ID
# Returns:
#   0 on success, 1 on failure
#######################################
transaction_start() {
    local operation="$1"
    local dataset_name="$2"
    local source_path="$3"
    local temp_path="$4"

    # Initialize transaction system
    if ! _tx_init; then
        return 1
    fi

    # Validate inputs
    if [[ -z "$operation" || -z "$dataset_name" || -z "$source_path" ]]; then
        echo "ERROR: transaction_start requires operation, dataset_name, and source_path" >&2
        return 1
    fi

    # Validate dataset name
    if ! validate_dataset_name "$dataset_name" 2>/dev/null; then
        echo "ERROR: Invalid dataset name: $dataset_name" >&2
        return 1
    fi

    # Generate transaction ID
    local tx_id=$(_tx_generate_id)
    local state_file=$(_tx_get_state_file "$tx_id")

    # Acquire lock
    local lock_fd
    lock_fd=$(_tx_acquire_lock "$tx_id") || return 1

    # Create transaction state
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    local state_content=$(cat <<EOF
{
  "transaction_id": "$tx_id",
  "operation": "$operation",
  "dataset_name": "$dataset_name",
  "source_path": "$source_path",
  "temp_path": "$temp_path",
  "state": "INITIATED",
  "created_at": "$timestamp",
  "updated_at": "$timestamp",
  "pid": $$,
  "hostname": "$(hostname)",
  "dry_run": "${DRY_RUN:-no}"
}
EOF
)

    # Write state file atomically
    if ! _tx_write_state_atomic "$state_file" "$state_content"; then
        _tx_release_lock "$tx_id" "$lock_fd"
        return 1
    fi

    # Release lock
    _tx_release_lock "$tx_id" "$lock_fd"

    # Log transaction start
    if declare -F log_message >/dev/null 2>&1; then
        log_message "INFO" "Transaction started: $tx_id (operation: $operation, dataset: $dataset_name)"
    fi

    # Output transaction ID
    echo "$tx_id"
    return 0
}

#######################################
# Update transaction state
# Arguments:
#   $1 - Transaction ID
#   $2 - New state
#   $3 - Optional error message
# Returns:
#   0 on success, 1 on failure
#######################################
transaction_update_state() {
    local tx_id="$1"
    local new_state="$2"
    local error_msg="${3:-}"

    if [[ -z "$tx_id" || -z "$new_state" ]]; then
        echo "ERROR: transaction_update_state requires tx_id and new_state" >&2
        return 1
    fi

    local state_file=$(_tx_get_state_file "$tx_id")

    if [[ ! -f "$state_file" ]]; then
        echo "ERROR: Transaction state file not found: $tx_id" >&2
        return 1
    fi

    # Acquire lock
    local lock_fd
    lock_fd=$(_tx_acquire_lock "$tx_id") || return 1

    # Read current state
    local current_state
    if ! current_state=$(cat "$state_file" 2>/dev/null); then
        echo "ERROR: Failed to read transaction state: $tx_id" >&2
        _tx_release_lock "$tx_id" "$lock_fd"
        return 1
    fi

    # Update state using jq if available, otherwise use sed
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    local updated_state

    if command -v jq >/dev/null 2>&1; then
        updated_state=$(echo "$current_state" | jq \
            --arg state "$new_state" \
            --arg time "$timestamp" \
            --arg err "$error_msg" \
            '.state = $state | .updated_at = $time | if $err != "" then .error_message = $err else . end')
    else
        # jq is required for safe JSON manipulation
        echo "ERROR: jq is required for transaction state updates but is not available" >&2
        echo "ERROR: Please install jq: sudo apt install jq" >&2
        _tx_release_lock "$tx_id" "$lock_fd"
        return 1
    fi

    # Write updated state atomically
    if ! _tx_write_state_atomic "$state_file" "$updated_state"; then
        _tx_release_lock "$tx_id" "$lock_fd"
        return 1
    fi

    # Release lock
    _tx_release_lock "$tx_id" "$lock_fd"

    # Log state update
    if declare -F log_message >/dev/null 2>&1; then
        log_message "INFO" "Transaction $tx_id state updated: $new_state"
    fi

    return 0
}

#######################################
# Mark transaction as completed
# Arguments:
#   $1 - Transaction ID
# Returns:
#   0 on success, 1 on failure
#######################################
transaction_complete() {
    local tx_id="$1"

    if [[ -z "$tx_id" ]]; then
        echo "ERROR: transaction_complete requires tx_id" >&2
        return 1
    fi

    if ! transaction_update_state "$tx_id" "COMPLETED"; then
        return 1
    fi

    if declare -F log_message >/dev/null 2>&1; then
        log_message "SUCCESS" "Transaction completed: $tx_id"
    fi

    return 0
}

#######################################
# Mark transaction as failed
# Arguments:
#   $1 - Transaction ID
#   $2 - Error message
# Returns:
#   0 on success, 1 on failure
#######################################
transaction_fail() {
    local tx_id="$1"
    local error_msg="$2"

    if [[ -z "$tx_id" ]]; then
        echo "ERROR: transaction_fail requires tx_id" >&2
        return 1
    fi

    if ! transaction_update_state "$tx_id" "FAILED" "$error_msg"; then
        return 1
    fi

    if declare -F log_message >/dev/null 2>&1; then
        log_message "ERROR" "Transaction failed: $tx_id - $error_msg"
    fi

    return 0
}

#######################################
# Get transaction information
# Arguments:
#   $1 - Transaction ID
#   $2 - Field name (optional, returns full JSON if not specified)
# Outputs:
#   Transaction information
# Returns:
#   0 on success, 1 on failure
#######################################
transaction_get_info() {
    local tx_id="$1"
    local field="${2:-}"

    if [[ -z "$tx_id" ]]; then
        echo "ERROR: transaction_get_info requires tx_id" >&2
        return 1
    fi

    local state_file=$(_tx_get_state_file "$tx_id")

    if [[ ! -f "$state_file" ]]; then
        echo "ERROR: Transaction state file not found: $tx_id" >&2
        return 1
    fi

    local state_content
    if ! state_content=$(cat "$state_file" 2>/dev/null); then
        echo "ERROR: Failed to read transaction state: $tx_id" >&2
        return 1
    fi

    if [[ -z "$field" ]]; then
        echo "$state_content"
    else
        if command -v jq >/dev/null 2>&1; then
            echo "$state_content" | jq -r ".$field"
        else
            # Fallback: grep and sed
            echo "$state_content" | grep "\"$field\"" | sed 's/.*: "\([^"]*\)".*/\1/'
        fi
    fi

    return 0
}

#######################################
# Rollback a transaction
# Attempts to restore the original state
# Arguments:
#   $1 - Transaction ID
# Returns:
#   0 on success, 1 on failure
#######################################
transaction_rollback() {
    local tx_id="$1"

    if [[ -z "$tx_id" ]]; then
        echo "ERROR: transaction_rollback requires tx_id" >&2
        return 1
    fi

    # Get transaction info
    local state
    state=$(transaction_get_info "$tx_id" "state")
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo "ERROR: Cannot get transaction state for $tx_id" >&2
        return 1
    fi

    # Don't rollback if already completed or rolled back
    if [[ "$state" == "COMPLETED" || "$state" == "ROLLEDBACK" ]]; then
        if declare -F log_message >/dev/null 2>&1; then
            log_message "INFO" "Transaction $tx_id already in final state ($state), no rollback needed"
        fi
        return 0
    fi

    local dataset_name
    dataset_name=$(transaction_get_info "$tx_id" "dataset_name")
    local source_path
    source_path=$(transaction_get_info "$tx_id" "source_path")
    local temp_path
    temp_path=$(transaction_get_info "$tx_id" "temp_path")

    if declare -F log_message >/dev/null 2>&1; then
        log_message "WARNING" "Rolling back transaction $tx_id (state: $state)"
    fi

    local rollback_success=true
    local dry_run
    dry_run=$(transaction_get_info "$tx_id" "dry_run")

    # Rollback based on current state
    case "$state" in
        "INITIATED")
            # No filesystem changes yet, nothing to rollback
            if declare -F log_message >/dev/null 2>&1; then
                log_message "INFO" "Transaction $tx_id in INITIATED state, no changes to rollback"
            fi
            ;;

        "RENAMED")
            # Restore original directory name from temp
            if [[ "$dry_run" != "yes" ]]; then
                if [[ -d "$temp_path" && ! -e "$source_path" ]]; then
                    if mv "$temp_path" "$source_path" 2>/dev/null; then
                        if declare -F log_message >/dev/null 2>&1; then
                            log_message "SUCCESS" "Restored original directory: $source_path"
                        fi
                    else
                        if declare -F log_message >/dev/null 2>&1; then
                            log_message "ERROR" "Failed to restore directory from $temp_path to $source_path"
                        fi
                        rollback_success=false
                    fi
                else
                    if declare -F log_message >/dev/null 2>&1; then
                        log_message "WARNING" "Cannot restore directory (temp not found or source exists)"
                    fi
                fi
            else
                if declare -F log_message >/dev/null 2>&1; then
                    log_message "INFO" "DRY RUN: Would restore directory from $temp_path to $source_path"
                fi
            fi
            ;;

        "DATASET_CREATED"|"RSYNC_STARTED"|"RSYNC_COMPLETE")
            # Dataset was created, need to destroy it and restore original
            if [[ "$dry_run" != "yes" ]]; then
                # Check if dataset exists
                if zfs list -H "$dataset_name" &>/dev/null; then
                    if zfs destroy -r "$dataset_name" 2>/dev/null; then
                        if declare -F log_message >/dev/null 2>&1; then
                            log_message "SUCCESS" "Destroyed dataset: $dataset_name"
                        fi
                    else
                        if declare -F log_message >/dev/null 2>&1; then
                            log_message "ERROR" "Failed to destroy dataset: $dataset_name"
                        fi
                        rollback_success=false
                    fi
                fi

                # Restore original directory if temp exists
                if [[ -d "$temp_path" && ! -e "$source_path" ]]; then
                    if mv "$temp_path" "$source_path" 2>/dev/null; then
                        if declare -F log_message >/dev/null 2>&1; then
                            log_message "SUCCESS" "Restored original directory: $source_path"
                        fi
                    else
                        if declare -F log_message >/dev/null 2>&1; then
                            log_message "ERROR" "Failed to restore directory from $temp_path to $source_path"
                        fi
                        rollback_success=false
                    fi
                fi
            else
                if declare -F log_message >/dev/null 2>&1; then
                    log_message "INFO" "DRY RUN: Would destroy dataset $dataset_name and restore directory"
                fi
            fi
            ;;

        "VALIDATED")
            # Data was validated - this is a forward recovery case
            # The operation nearly succeeded, so we should complete it rather than rollback
            if declare -F log_message >/dev/null 2>&1; then
                log_message "INFO" "Transaction $tx_id in VALIDATED state - completing rather than rolling back"
            fi

            if [[ "$dry_run" != "yes" ]]; then
                # Remove temp directory
                if [[ -d "$temp_path" ]]; then
                    if rm -rf "$temp_path" 2>/dev/null; then
                        if declare -F log_message >/dev/null 2>&1; then
                            log_message "SUCCESS" "Cleaned up temporary directory: $temp_path"
                        fi
                    fi
                fi
            fi

            # Mark as completed instead of rolledback
            transaction_complete "$tx_id"
            return 0
            ;;

        "FAILED")
            # Already marked as failed, attempt cleanup
            if declare -F log_message >/dev/null 2>&1; then
                log_message "WARNING" "Transaction $tx_id already marked as FAILED, attempting cleanup"
            fi

            # Try to clean up any partial state
            if [[ "$dry_run" != "yes" ]]; then
                if [[ -d "$temp_path" && ! -e "$source_path" ]]; then
                    mv "$temp_path" "$source_path" 2>/dev/null || true
                fi
            fi
            ;;

        *)
            if declare -F log_message >/dev/null 2>&1; then
                log_message "ERROR" "Unknown transaction state: $state"
            fi
            rollback_success=false
            ;;
    esac

    # Update transaction state
    if [[ "$rollback_success" == true ]]; then
        transaction_update_state "$tx_id" "ROLLEDBACK"
        return 0
    else
        transaction_update_state "$tx_id" "FAILED" "Rollback failed"
        return 1
    fi
}

#######################################
# List all pending transactions
# Outputs:
#   List of transaction IDs with their states
# Returns:
#   0 on success
#######################################
transaction_list_pending() {
    _tx_init || return 1

    if [[ ! -d "$TX_STATE_DIR" ]]; then
        return 0
    fi

    local found_any=false

    for state_file in "$TX_STATE_DIR"/tx_*.json; do
        [[ ! -f "$state_file" ]] && continue

        local tx_id=$(basename "$state_file" .json)
        local state
        state=$(transaction_get_info "$tx_id" "state")

        # Only show non-final states
        if [[ "$state" != "COMPLETED" && "$state" != "ROLLEDBACK" ]]; then
            local dataset
            dataset=$(transaction_get_info "$tx_id" "dataset_name")
            local created
            created=$(transaction_get_info "$tx_id" "created_at")
            echo "$tx_id | State: $state | Dataset: $dataset | Created: $created"
            found_any=true
        fi
    done

    if [[ "$found_any" == false ]]; then
        echo "No pending transactions found"
    fi

    return 0
}

#######################################
# Recover all pending transactions
# Attempts to complete or rollback pending transactions
# Returns:
#   0 on success
#######################################
transaction_recover_all() {
    if declare -F log_message >/dev/null 2>&1; then
        log_message "INFO" "Scanning for pending transactions to recover..."
    fi

    _tx_init || return 1

    if [[ ! -d "$TX_STATE_DIR" ]]; then
        return 0
    fi

    local recovered_count=0
    local failed_count=0

    for state_file in "$TX_STATE_DIR"/tx_*.json; do
        [[ ! -f "$state_file" ]] && continue

        local tx_id=$(basename "$state_file" .json)
        local state
        state=$(transaction_get_info "$tx_id" "state")

        # Skip if already in final state
        if [[ "$state" == "COMPLETED" || "$state" == "ROLLEDBACK" ]]; then
            continue
        fi

        if declare -F log_message >/dev/null 2>&1; then
            log_message "WARNING" "Found pending transaction: $tx_id (state: $state)"
        fi

        # Attempt recovery based on state
        case "$state" in
            "VALIDATED")
                # Forward recovery - complete the transaction
                if declare -F log_message >/dev/null 2>&1; then
                    log_message "INFO" "Attempting forward recovery for $tx_id"
                fi

                local temp_path
                temp_path=$(transaction_get_info "$tx_id" "temp_path")

                if [[ -d "$temp_path" ]]; then
                    rm -rf "$temp_path" 2>/dev/null || true
                fi

                transaction_complete "$tx_id"
                recovered_count=$((recovered_count + 1))
                ;;

            *)
                # Rollback for all other states
                if declare -F log_message >/dev/null 2>&1; then
                    log_message "INFO" "Attempting rollback for $tx_id"
                fi

                if transaction_rollback "$tx_id"; then
                    recovered_count=$((recovered_count + 1))
                else
                    failed_count=$((failed_count + 1))
                fi
                ;;
        esac
    done

    if declare -F log_message >/dev/null 2>&1; then
        if [[ $recovered_count -gt 0 || $failed_count -gt 0 ]]; then
            log_message "INFO" "Transaction recovery complete: $recovered_count recovered, $failed_count failed"
        else
            log_message "INFO" "No pending transactions found"
        fi
    fi

    return 0
}

#######################################
# Clean up old completed transaction files
# Arguments:
#   $1 - Age in days (default: 30)
# Returns:
#   0 on success
#######################################
transaction_cleanup() {
    local age_days="${1:-30}"

    _tx_init || return 1

    if [[ ! -d "$TX_STATE_DIR" ]]; then
        return 0
    fi

    local cleaned_count=0

    for state_file in "$TX_STATE_DIR"/tx_*.json; do
        [[ ! -f "$state_file" ]] && continue

        local tx_id=$(basename "$state_file" .json)
        local state
        state=$(transaction_get_info "$tx_id" "state")

        # Only clean up completed or rolled back transactions
        if [[ "$state" != "COMPLETED" && "$state" != "ROLLEDBACK" ]]; then
            continue
        fi

        # Check file age
        local file_age_days
        if command -v stat >/dev/null 2>&1; then
            local file_mtime=$(stat -c %Y "$state_file" 2>/dev/null || echo 0)
            local current_time=$(date +%s)
            file_age_days=$(( (current_time - file_mtime) / 86400 ))
        else
            # Fallback: use find
            if find "$state_file" -mtime +"$age_days" 2>/dev/null | grep -q .; then
                file_age_days=$((age_days + 1))
            else
                file_age_days=0
            fi
        fi

        if [[ $file_age_days -ge $age_days ]]; then
            if rm -f "$state_file" 2>/dev/null; then
                cleaned_count=$((cleaned_count + 1))
            fi
        fi
    done

    if declare -F log_message >/dev/null 2>&1 && [[ $cleaned_count -gt 0 ]]; then
        log_message "INFO" "Cleaned up $cleaned_count old transaction files (older than $age_days days)"
    fi

    return 0
}

# Export transaction functions
export -f transaction_start
export -f transaction_update_state
export -f transaction_complete
export -f transaction_fail
export -f transaction_rollback
export -f transaction_get_info
export -f transaction_list_pending
export -f transaction_recover_all
export -f transaction_cleanup
