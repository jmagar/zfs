#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   ZFS Error Handling Library                                            # #
# #   Provides comprehensive error handling and recovery functions         # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Enable error tracking
set -o pipefail

# Global error state
declare -g ZFS_ERROR_COUNT=0
declare -g ZFS_LAST_ERROR=""
declare -g ZFS_ERROR_LOG="${ZFS_ERROR_LOG:-/var/log/zfs-errors.log}"

#######################################
# Log error and increment counter
# Globals:
#   ZFS_ERROR_COUNT
#   ZFS_LAST_ERROR
#   ZFS_ERROR_LOG
# Arguments:
#   $1 - Error message
#   $2 - Error code (optional)
# Returns:
#   Error code or 1
#######################################
error() {
    local message="$1"
    local code="${2:-1}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    ZFS_ERROR_COUNT=$((ZFS_ERROR_COUNT + 1))
    ZFS_LAST_ERROR="$message"

    # Ensure error log directory exists
    local error_log_dir=$(dirname "$ZFS_ERROR_LOG")
    if [[ ! -d "$error_log_dir" ]]; then
        mkdir -p "$error_log_dir" 2>/dev/null || true
    fi

    # Log to error log file
    echo "[$timestamp] [ERROR $code] $message" >> "$ZFS_ERROR_LOG" 2>/dev/null || true

    # Also log via standard logging if available
    if declare -F log_message >/dev/null 2>&1; then
        log_message "ERROR" "$message"
    else
        echo "ERROR: $message" >&2
    fi

    return "$code"
}

#######################################
# Execute command with error handling
# Arguments:
#   $@ - Command and arguments
# Returns:
#   Command exit code
# Outputs:
#   Command output and error on failure
#######################################
safe_execute() {
    local cmd=("$@")
    local output
    local exit_code

    # Execute command and capture output
    if output=$("${cmd[@]}" 2>&1); then
        exit_code=0
    else
        exit_code=$?
        error "Command failed (exit $exit_code): ${cmd[*]}" "$exit_code"
        echo "$output" >&2
    fi

    return "$exit_code"
}

#######################################
# Execute command with retry logic
# Implements exponential backoff for retries
# Arguments:
#   $1 - Max retry attempts
#   $2+ - Command and arguments
# Returns:
#   0 on success, last exit code on failure
#######################################
retry_execute() {
    local max_attempts="$1"
    shift
    local cmd=("$@")
    local attempt=1
    local exit_code

    # Validate max_attempts
    if [[ ! "$max_attempts" =~ ^[0-9]+$ ]] || [[ "$max_attempts" -lt 1 ]]; then
        error "retry_execute: max_attempts must be a positive integer"
        return 1
    fi

    while (( attempt <= max_attempts )); do
        if "${cmd[@]}"; then
            return 0
        else
            exit_code=$?
            if (( attempt < max_attempts )); then
                # Exponential backoff: 2^(attempt-1) seconds
                local wait_time=$((2 ** (attempt - 1)))
                if declare -F log_message >/dev/null 2>&1; then
                    log_message "WARNING" "Command failed (attempt $attempt/$max_attempts), retrying in ${wait_time}s: ${cmd[*]}"
                else
                    echo "WARNING: Command failed (attempt $attempt/$max_attempts), retrying in ${wait_time}s: ${cmd[*]}" >&2
                fi
                sleep "$wait_time"
            fi
            attempt=$((attempt + 1))
        fi
    done

    error "Command failed after $max_attempts attempts: ${cmd[*]}" "$exit_code"
    return "$exit_code"
}

#######################################
# Check if command succeeded
# Arguments:
#   $1 - Exit code to check
#   $2 - Error message if failed
# Returns:
#   0 if success, 1 if failed
#######################################
check_exit_code() {
    local exit_code="$1"
    local message="$2"

    if [[ ! "$exit_code" =~ ^[0-9]+$ ]]; then
        error "check_exit_code: exit code must be an integer, got: $exit_code"
        return 1
    fi

    if [[ "$exit_code" -ne 0 ]]; then
        error "$message (exit code: $exit_code)" "$exit_code"
        return 1
    fi

    return 0
}

#######################################
# Require command to succeed or exit
# Arguments:
#   $@ - Command and arguments
# Returns:
#   Never returns on failure (exits script)
#######################################
require() {
    local cmd=("$@")

    if ! "${cmd[@]}"; then
        local exit_code=$?
        error "FATAL: Required command failed: ${cmd[*]}" "$exit_code"
        exit "$exit_code"
    fi
}

#######################################
# Execute command in dry-run mode
# Globals:
#   DRY_RUN
# Arguments:
#   $@ - Command and arguments
# Returns:
#   0 in dry-run, command exit code otherwise
#######################################
dry_run_execute() {
    local cmd=("$@")

    if [[ "${DRY_RUN:-no}" == "yes" ]]; then
        if declare -F log_message >/dev/null 2>&1; then
            log_message "INFO" "DRY RUN: Would execute: ${cmd[*]}"
        else
            echo "DRY RUN: Would execute: ${cmd[*]}"
        fi
        return 0
    else
        "${cmd[@]}"
        return $?
    fi
}

#######################################
# Verify file exists and is readable
# Arguments:
#   $1 - File path
# Returns:
#   0 if exists and readable, 1 otherwise
#######################################
require_file() {
    local file="$1"

    if [[ -z "$file" ]]; then
        error "require_file: file path cannot be empty"
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        error "Required file does not exist: $file"
        return 1
    fi

    if [[ ! -r "$file" ]]; then
        error "Required file is not readable: $file"
        return 1
    fi

    return 0
}

#######################################
# Verify directory exists and is writable
# Arguments:
#   $1 - Directory path
# Returns:
#   0 if exists and writable, 1 otherwise
#######################################
require_directory() {
    local dir="$1"

    if [[ -z "$dir" ]]; then
        error "require_directory: directory path cannot be empty"
        return 1
    fi

    if [[ ! -d "$dir" ]]; then
        error "Required directory does not exist: $dir"
        return 1
    fi

    if [[ ! -w "$dir" ]]; then
        error "Required directory is not writable: $dir"
        return 1
    fi

    return 0
}

#######################################
# Verify command exists in PATH
# Arguments:
#   $1 - Command name
# Returns:
#   0 if exists, 1 otherwise
#######################################
require_command() {
    local cmd="$1"

    if [[ -z "$cmd" ]]; then
        error "require_command: command name cannot be empty"
        return 1
    fi

    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "Required command not found: $cmd"
        return 1
    fi

    return 0
}

#######################################
# Cleanup function to call on exit
# Usage: trap cleanup_on_exit EXIT
# Globals:
#   ZFS_ERROR_COUNT
#   ZFS_LAST_ERROR
# Returns:
#   None
#######################################
cleanup_on_exit() {
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        if declare -F log_message >/dev/null 2>&1; then
            log_message "ERROR" "Script exited with error code: $exit_code"
            log_message "ERROR" "Total errors encountered: $ZFS_ERROR_COUNT"
            if [[ -n "$ZFS_LAST_ERROR" ]]; then
                log_message "ERROR" "Last error: $ZFS_LAST_ERROR"
            fi
        else
            echo "ERROR: Script exited with error code: $exit_code" >&2
            echo "ERROR: Total errors encountered: $ZFS_ERROR_COUNT" >&2
            if [[ -n "$ZFS_LAST_ERROR" ]]; then
                echo "ERROR: Last error: $ZFS_LAST_ERROR" >&2
            fi
        fi
    fi

    # Call user-defined cleanup if available
    if declare -F user_cleanup >/dev/null 2>&1; then
        user_cleanup
    fi
}

#######################################
# Reset error counter
# Globals:
#   ZFS_ERROR_COUNT
#   ZFS_LAST_ERROR
# Returns:
#   None
#######################################
reset_error_count() {
    ZFS_ERROR_COUNT=0
    ZFS_LAST_ERROR=""
}

#######################################
# Get error count
# Globals:
#   ZFS_ERROR_COUNT
# Returns:
#   Current error count
# Outputs:
#   Error count to stdout
#######################################
get_error_count() {
    echo "$ZFS_ERROR_COUNT"
}

#######################################
# Get last error message
# Globals:
#   ZFS_LAST_ERROR
# Returns:
#   None
# Outputs:
#   Last error message to stdout
#######################################
get_last_error() {
    echo "$ZFS_LAST_ERROR"
}

# Export error handling functions
export -f error
export -f safe_execute
export -f retry_execute
export -f check_exit_code
export -f require
export -f dry_run_execute
export -f require_file
export -f require_directory
export -f require_command
export -f cleanup_on_exit
export -f reset_error_count
export -f get_error_count
export -f get_last_error

# Set up exit trap (skip in test environments)
# BATS sets BATS_VERSION when running tests
if [[ -z "${BATS_VERSION:-}" ]]; then
    trap cleanup_on_exit EXIT
fi
