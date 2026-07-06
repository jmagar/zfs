#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   ZFS Input Validation Library                                          # #
# #   Provides comprehensive input validation functions for ZFS scripts    # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# This library provides validation functions for:
# - ZFS dataset and pool names
# - Filesystem paths with traversal protection
# - Integer values and ranges
# - URLs and hostnames
# - ZFS resource existence checks
# - Snapshot name formats
#
# All validation functions return 0 on success, 1 on failure
# Error messages are sent to stderr
#
# Usage:
#   source lib/zfs-validation.sh
#   if validate_dataset_name "tank/data"; then
#       echo "Valid dataset name"
#   fi
#
# Requirements:
#   - Bash 4.0 or higher
#   - ZFS utilities (for existence checks)
#   - realpath command (for path validation)

#######################################
# Validate ZFS dataset name
#
# ZFS dataset naming rules:
# - Must start with alphanumeric character
# - Can contain: a-z A-Z 0-9 _ : . -
# - Can use / for hierarchy (pool/dataset/child)
# - Cannot have consecutive slashes
# - Cannot end with slash
# - Cannot use reserved names (.zfs, snapshot, bookmark)
# - Maximum length: 255 characters
#
# Globals:
#   None
# Arguments:
#   $1 - Dataset name to validate
# Returns:
#   0 on valid, 1 on invalid
# Outputs:
#   Error message to stderr if invalid
#######################################
validate_dataset_name() {
    local name="$1"

    if [[ -z "$name" ]]; then
        echo "ERROR: Dataset name cannot be empty" >&2
        return 1
    fi

    # Check basic format: must start with alphanumeric, can contain valid chars
    # Valid chars: a-zA-Z0-9_:.-/ (slash only for hierarchy)
    if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_:.-]*(\/[a-zA-Z0-9][a-zA-Z0-9_:.-]*)*$ ]]; then
        echo "ERROR: Invalid dataset name format: $name" >&2
        echo "Dataset names must start with alphanumeric, and contain only [a-zA-Z0-9_:.-/]" >&2
        return 1
    fi

    # Check for consecutive slashes
    if [[ "$name" =~ // ]]; then
        echo "ERROR: Dataset name cannot contain consecutive slashes: $name" >&2
        return 1
    fi

    # Check if ends with slash
    if [[ "$name" =~ /$ ]]; then
        echo "ERROR: Dataset name cannot end with slash: $name" >&2
        return 1
    fi

    # Check for ZFS reserved names in any component
    local IFS='/'
# shellcheck disable=SC2206
        local -a components=($name)
    for component in "${components[@]}"; do
        case "$component" in
            ".zfs"|"snapshot"|"bookmark")
                echo "ERROR: Dataset name component uses ZFS reserved word: $component" >&2
                return 1
                ;;
        esac
    done

    # Check length (ZFS has a max path length)
    if [[ ${#name} -gt 255 ]]; then
        echo "ERROR: Dataset name too long (max 255 characters): ${#name}" >&2
        return 1
    fi

    return 0
}

#######################################
# Validate filesystem path
#
# Performs comprehensive path validation including:
# - Non-empty check
# - Path traversal protection (..)
# - Null byte detection
# - Control character detection
# - Optional base path containment check
#
# Globals:
#   None
# Arguments:
#   $1 - Path to validate
#   $2 - Base path (optional, for containment validation)
# Returns:
#   0 on valid, 1 on invalid
# Outputs:
#   Error message to stderr if invalid
#######################################
validate_path() {
    local path="$1"
    local base_path="${2:-}"

    if [[ -z "$path" ]]; then
        echo "ERROR: Path cannot be empty" >&2
        return 1
    fi

    # Check for path traversal attempts (../ or /.. but not file..txt)
    if [[ "$path" =~ (\.\./|/\.\.) ]]; then
        echo "ERROR: Path contains parent directory reference (..): $path" >&2
        return 1
    fi

    # Check for null bytes
    if [[ "$path" =~ $'\0' ]]; then
        echo "ERROR: Path contains null byte" >&2
        return 1
    fi

    # Check for control characters
    if [[ "$path" =~ [[:cntrl:]] ]]; then
        echo "ERROR: Path contains control characters: $path" >&2
        return 1
    fi

    # If base path provided, ensure path is within it
    if [[ -n "$base_path" ]]; then
        local real_path
        local real_base

        # Use realpath -m to resolve without requiring existence
        if ! real_path=$(realpath -m "$path" 2>/dev/null); then
            echo "ERROR: Cannot resolve path: $path" >&2
            return 1
        fi

        if ! real_base=$(realpath -m "$base_path" 2>/dev/null); then
            echo "ERROR: Cannot resolve base path: $base_path" >&2
            return 1
        fi

        # Ensure real_path starts with real_base followed by / or is exactly equal
        if [[ ! "$real_path" =~ ^"$real_base"(/|$) ]]; then
            echo "ERROR: Path $path is outside base path $base_path" >&2
            return 1
        fi
    fi

    return 0
}

#######################################
# Validate positive integer (> 0)
#
# Checks that value is:
# - Numeric
# - Integer (no decimals)
# - Greater than zero
#
# Arguments:
#   $1 - Value to validate
#   $2 - Variable name (for error messages, optional)
# Returns:
#   0 on valid, 1 on invalid
# Outputs:
#   Error message to stderr if invalid
#######################################
validate_positive_integer() {
    local value="$1"
    local name="${2:-value}"

    # Check if it's a number
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        echo "ERROR: $name must be a positive integer, got: $value" >&2
        return 1
    fi

    # Check if greater than 0
    if [[ "$value" -eq 0 ]]; then
        echo "ERROR: $name must be greater than 0" >&2
        return 1
    fi

    return 0
}

#######################################
# Validate non-negative integer (>= 0)
#
# Checks that value is:
# - Numeric
# - Integer (no decimals)
# - Zero or greater
#
# Arguments:
#   $1 - Value to validate
#   $2 - Variable name (for error messages, optional)
# Returns:
#   0 on valid, 1 on invalid
# Outputs:
#   Error message to stderr if invalid
#######################################
validate_non_negative_integer() {
    local value="$1"
    local name="${2:-value}"

    # Check if it's a number (allows 0)
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        echo "ERROR: $name must be a non-negative integer, got: $value" >&2
        return 1
    fi

    return 0
}

#######################################
# Validate integer in range [min, max]
#
# Checks that value is:
# - A non-negative integer
# - Within specified range (inclusive)
#
# Arguments:
#   $1 - Value to validate
#   $2 - Minimum value (inclusive)
#   $3 - Maximum value (inclusive)
#   $4 - Variable name (for error messages, optional)
# Returns:
#   0 on valid, 1 on invalid
# Outputs:
#   Error message to stderr if invalid
#######################################
validate_integer_range() {
    local value="$1"
    local min="$2"
    local max="$3"
    local name="${4:-value}"

    # First validate it's a non-negative integer
    if ! validate_non_negative_integer "$value" "$name"; then
        return 1
    fi

    # Check range
    if [[ "$value" -lt "$min" || "$value" -gt "$max" ]]; then
        echo "ERROR: $name must be between $min and $max, got: $value" >&2
        return 1
    fi

    return 0
}

#######################################
# Validate URL format
#
# Basic URL validation for http/https URLs:
# - Must start with http:// or https://
# - Valid hostname format
# - Optional port number
# - Optional path
# - No spaces or path traversal
#
# Arguments:
#   $1 - URL to validate
# Returns:
#   0 on valid, 1 on invalid
# Outputs:
#   Error message to stderr if invalid
#######################################
validate_url() {
    local url="$1"

    if [[ -z "$url" ]]; then
        echo "ERROR: URL cannot be empty" >&2
        return 1
    fi

    # Basic URL validation: protocol://host[:port][/path]
    # Accepts hostnames and IPv4 addresses, with optional port and path
    local ipv4='([0-9]{1,3}\.){3}[0-9]{1,3}'
    local hostname='[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*'
    if [[ ! "$url" =~ ^https?://($hostname|$ipv4)(:[0-9]{1,5})?(/.*)?$ ]]; then
        echo "ERROR: Invalid URL format: $url" >&2
        return 1
    fi

    # Check for spaces
    if [[ "$url" =~ [[:space:]] ]]; then
        echo "ERROR: URL contains spaces: $url" >&2
        return 1
    fi

    # Check for path traversal in URL path
    if [[ "$url" =~ \.\./ ]]; then
        echo "ERROR: URL contains path traversal: $url" >&2
        return 1
    fi

    return 0
}

#######################################
# Validate hostname or IP address
#
# Validates either:
# - IPv4 address (dotted decimal notation)
# - Hostname (RFC 1123 compliant)
#
# Arguments:
#   $1 - Host to validate
# Returns:
#   0 on valid, 1 on invalid
# Outputs:
#   Error message to stderr if invalid
#######################################
validate_host() {
    local host="$1"

    if [[ -z "$host" ]]; then
        echo "ERROR: Host cannot be empty" >&2
        return 1
    fi

    # Check if it's an IPv4 address
    if [[ "$host" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # Validate each octet (0-255)
        local IFS='.'
# shellcheck disable=SC2206
                local -a octets=($host)
        for octet in "${octets[@]}"; do
            # Remove leading zeros for comparison
            local num=$((10#$octet))
            if [[ "$num" -gt 255 ]]; then
                echo "ERROR: Invalid IPv4 address: $host (octet $octet > 255)" >&2
                return 1
            fi
        done
        return 0
    fi

    # Check if it's a valid hostname (RFC 1123)
    # - Labels can contain alphanumeric and hyphens
    # - Labels must start and end with alphanumeric
    # - Labels can be 1-63 characters
    # - Total hostname up to 253 characters
    if [[ "$host" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        # Check total length
        if [[ ${#host} -gt 253 ]]; then
            echo "ERROR: Hostname too long (max 253 characters): $host" >&2
            return 1
        fi
        return 0
    fi

    echo "ERROR: Invalid hostname or IP address: $host" >&2
    return 1
}

#######################################
# Validate ZFS pool exists
#
# Checks if the specified ZFS pool:
# - Has a valid name format
# - Actually exists in the system
#
# Arguments:
#   $1 - Pool name
# Returns:
#   0 if exists and valid, 1 otherwise
# Outputs:
#   Error message to stderr if invalid
#######################################
validate_pool_exists() {
    local pool="$1"

    # Validate the name format first
    if ! validate_dataset_name "$pool"; then
        return 1
    fi

    # Check if pool exists
    if ! zpool list -H "$pool" &>/dev/null; then
        echo "ERROR: ZFS pool does not exist: $pool" >&2
        return 1
    fi

    return 0
}

#######################################
# Validate ZFS dataset exists
#
# Checks if the specified ZFS dataset:
# - Has a valid name format
# - Actually exists in the system
#
# Arguments:
#   $1 - Dataset name (can be pool/dataset/child)
# Returns:
#   0 if exists and valid, 1 otherwise
# Outputs:
#   Error message to stderr if invalid
#######################################
validate_dataset_exists() {
    local dataset="$1"

    # Validate the name format first
    if ! validate_dataset_name "$dataset"; then
        return 1
    fi

    # Check if dataset exists
    if ! zfs list -H "$dataset" &>/dev/null; then
        echo "ERROR: ZFS dataset does not exist: $dataset" >&2
        return 1
    fi

    return 0
}

#######################################
# Validate ZFS snapshot name format
#
# Validates snapshot name in format: dataset@snapshot
# - Dataset part must be valid dataset name
# - Snapshot part must be valid (alphanumeric, _, :, ., -)
# - Must contain exactly one @
#
# Arguments:
#   $1 - Snapshot name (dataset@snapshot)
# Returns:
#   0 on valid, 1 on invalid
# Outputs:
#   Error message to stderr if invalid
#######################################
validate_snapshot_name() {
    local snapshot="$1"

    if [[ -z "$snapshot" ]]; then
        echo "ERROR: Snapshot name cannot be empty" >&2
        return 1
    fi

    # Check format: dataset@snapshot
    if [[ ! "$snapshot" =~ ^(.+)@([^@]+)$ ]]; then
        echo "ERROR: Invalid snapshot format, expected dataset@snapshot: $snapshot" >&2
        return 1
    fi

    local dataset="${BASH_REMATCH[1]}"
    local snap="${BASH_REMATCH[2]}"

    # Validate dataset part
    if ! validate_dataset_name "$dataset"; then
        return 1
    fi

    # Validate snapshot name part
    # Snapshot names have similar rules but no slashes
    if [[ ! "$snap" =~ ^[a-zA-Z0-9][a-zA-Z0-9_:.-]*$ ]]; then
        echo "ERROR: Invalid snapshot name format: $snap" >&2
        echo "Snapshot names must start with alphanumeric, and contain only [a-zA-Z0-9_:.-]" >&2
        return 1
    fi

    # Check length
    if [[ ${#snap} -gt 255 ]]; then
        echo "ERROR: Snapshot name too long (max 255 characters): ${#snap}" >&2
        return 1
    fi

    return 0
}

#######################################
# Validate boolean value
#
# Checks if value is a valid boolean string
#
# Arguments:
#   $1 - Value to validate
#   $2 - Variable name (for error messages, optional)
# Returns:
#   0 on valid, 1 on invalid
# Outputs:
#   Error message to stderr if invalid
#######################################
validate_boolean() {
    local value="$1"
    local name="${2:-value}"

    case "$value" in
        "yes"|"no")
            return 0
            ;;
        *)
            echo "ERROR: $name must be 'yes' or 'no', got: $value" >&2
            return 1
            ;;
    esac
}

#######################################
# Validate choice from list
#
# Checks if value is one of the allowed choices
#
# Arguments:
#   $1 - Value to validate
#   $2 - Variable name (for error messages)
#   $@ - List of valid choices
# Returns:
#   0 on valid, 1 on invalid
# Outputs:
#   Error message to stderr if invalid
#######################################
validate_choice() {
    local value="$1"
    local name="$2"
    shift 2
    local -a choices=("$@")

    for choice in "${choices[@]}"; do
        if [[ "$value" == "$choice" ]]; then
            return 0
        fi
    done

    echo "ERROR: $name must be one of: ${choices[*]}, got: $value" >&2
    return 1
}

# Export validation functions for use in other scripts
export -f validate_dataset_name
export -f validate_path
export -f validate_positive_integer
export -f validate_non_negative_integer
export -f validate_integer_range
export -f validate_url
export -f validate_host
export -f validate_pool_exists
export -f validate_dataset_exists
export -f validate_snapshot_name
export -f validate_boolean
export -f validate_choice
