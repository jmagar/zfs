#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   Manual Recovery Script for ZFS Transaction Management                # #
# #   Provides interactive recovery for partial dataset conversions       # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Get the directory where this script is located
SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

# Source the transaction library
if [[ -f "$SCRIPT_DIR/lib/zfs-transactions.sh" ]]; then
    # shellcheck disable=SC1091 # runtime-resolved library, linted separately
    source "$SCRIPT_DIR/lib/zfs-transactions.sh"
else
    echo "ERROR: Cannot find lib/zfs-transactions.sh" >&2
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  ZFS Transaction Manual Recovery${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

print_info() {
    echo -e "${BLUE}INFO: $1${NC}"
}

list_pending_transactions() {
    print_header
    echo "Pending Transactions:"
    echo ""

    transaction_list_pending

    echo ""
}

show_transaction_details() {
    local tx_id="$1"

    echo ""
    echo -e "${BLUE}Transaction Details:${NC}"
    echo "===================="
    echo ""

    # Get transaction info
    local info
    info=$(transaction_get_info "$tx_id")

    if [[ -z "$info" ]]; then
        print_error "Transaction not found: $tx_id"
        return 1
    fi

    # Parse and display info
    echo "$info" | while IFS= read -r line; do
        echo "  $line"
    done

    echo ""

    # Get specific fields for filesystem check
    local state
    state=$(transaction_get_info "$tx_id" "state")
    local source_path
    source_path=$(transaction_get_info "$tx_id" "source_path")
    local temp_path
    temp_path=$(transaction_get_info "$tx_id" "temp_path")
    local dataset_name
    dataset_name=$(transaction_get_info "$tx_id" "dataset_name")

    echo -e "${BLUE}Filesystem Status:${NC}"
    echo "===================="
    echo ""

    # Check source path
    echo "Source Path: $source_path"
    if [[ -d "$source_path" ]]; then
        local size
        size=$(du -sh "$source_path" 2>/dev/null | cut -f1)
        local files
        files=$(find "$source_path" -type f 2>/dev/null | wc -l)
        echo -e "  ${GREEN}EXISTS${NC} - Size: $size, Files: $files"
    else
        echo -e "  ${RED}NOT FOUND${NC}"
    fi
    echo ""

    # Check temp path
    echo "Temp Path: $temp_path"
    if [[ -d "$temp_path" ]]; then
        local size
        size=$(du -sh "$temp_path" 2>/dev/null | cut -f1)
        local files
        files=$(find "$temp_path" -type f 2>/dev/null | wc -l)
        echo -e "  ${YELLOW}EXISTS${NC} - Size: $size, Files: $files"
    else
        echo "  NOT FOUND"
    fi
    echo ""

    # Check dataset
    echo "Dataset: $dataset_name"
    if zfs list -H "$dataset_name" &>/dev/null; then
        local used
        used=$(zfs list -H -o used "$dataset_name")
        local avail
        avail=$(zfs list -H -o avail "$dataset_name")
        echo -e "  ${GREEN}EXISTS${NC} - Used: $used, Available: $avail"
    else
        echo "  NOT FOUND"
    fi
    echo ""

    # Provide recommendation
    echo -e "${BLUE}Recommendation:${NC}"
    echo "===================="
    case "$state" in
        "INITIATED")
            echo "No filesystem changes yet. Safe to rollback or complete."
            ;;
        "RENAMED")
            echo "Directory renamed to temp. Rollback will restore original name."
            ;;
        "DATASET_CREATED"|"RSYNC_STARTED"|"RSYNC_COMPLETE")
            echo "Dataset exists. Rollback will destroy dataset and restore original directory."
            print_warning "Check if any data is already in the dataset before rollback!"
            ;;
        "VALIDATED")
            echo "Data validated. Forward recovery will complete cleanup."
            echo "This is the safest state - data is verified."
            ;;
        "COMPLETED")
            echo "Transaction already completed. No action needed."
            ;;
        "FAILED")
            echo "Transaction failed. Review error and decide on rollback."
            ;;
        "ROLLEDBACK")
            echo "Transaction already rolled back. No action needed."
            ;;
        *)
            echo "Unknown state. Manual intervention may be required."
            ;;
    esac
    echo ""
}

rollback_transaction() {
    local tx_id="$1"

    echo ""
    echo -e "${YELLOW}WARNING: About to rollback transaction $tx_id${NC}"
    echo ""

    # Show current state
    show_transaction_details "$tx_id"

    read -r -p "Are you sure you want to rollback? (type 'yes' to confirm): " confirm

    if [[ "$confirm" != "yes" ]]; then
        print_info "Rollback cancelled"
        return 0
    fi

    echo ""
    print_info "Rolling back transaction $tx_id..."

    if transaction_rollback "$tx_id"; then
        print_success "Rollback completed"

        # Show final state
        local final_state
        final_state=$(transaction_get_info "$tx_id" "state")
        echo ""
        echo "Final state: $final_state"
    else
        print_error "Rollback failed - check logs"
        return 1
    fi

    echo ""
}

recover_all_transactions() {
    print_header
    echo "Automatic Recovery of All Pending Transactions"
    echo ""
    print_warning "This will attempt to recover ALL pending transactions automatically"
    echo ""

    # Show what will be recovered
    echo "Pending transactions:"
    transaction_list_pending
    echo ""

    read -r -p "Proceed with automatic recovery? (type 'yes' to confirm): " confirm

    if [[ "$confirm" != "yes" ]]; then
        print_info "Automatic recovery cancelled"
        return 0
    fi

    echo ""
    print_info "Starting automatic recovery..."
    echo ""

    transaction_recover_all

    echo ""
    print_success "Automatic recovery completed"
    echo ""
    echo "Remaining pending transactions:"
    transaction_list_pending
    echo ""
}

cleanup_old_transactions() {
    local age_days="${1:-30}"

    print_header
    echo "Cleanup Old Transaction Files"
    echo ""
    echo "This will remove completed/rolled back transactions older than $age_days days"
    echo ""

    read -r -p "Proceed with cleanup? (type 'yes' to confirm): " confirm

    if [[ "$confirm" != "yes" ]]; then
        print_info "Cleanup cancelled"
        return 0
    fi

    echo ""
    print_info "Cleaning up old transactions..."

    transaction_cleanup "$age_days"

    echo ""
    print_success "Cleanup completed"
    echo ""
}

interactive_mode() {
    while true; do
        print_header
        echo "Please select an option:"
        echo ""
        echo "  1) List pending transactions"
        echo "  2) Show transaction details"
        echo "  3) Rollback specific transaction"
        echo "  4) Recover all pending transactions"
        echo "  5) Cleanup old transactions"
        echo "  6) Exit"
        echo ""
        read -r -p "Enter choice [1-6]: " choice

        case "$choice" in
            1)
                list_pending_transactions
                read -r -p "Press Enter to continue..."
                ;;
            2)
                echo ""
                read -r -p "Enter transaction ID: " tx_id
                show_transaction_details "$tx_id"
                read -r -p "Press Enter to continue..."
                ;;
            3)
                echo ""
                read -r -p "Enter transaction ID: " tx_id
                rollback_transaction "$tx_id"
                read -r -p "Press Enter to continue..."
                ;;
            4)
                recover_all_transactions
                read -r -p "Press Enter to continue..."
                ;;
            5)
                echo ""
                read -r -p "Enter age in days (default: 30): " age
                age=${age:-30}
                cleanup_old_transactions "$age"
                read -r -p "Press Enter to continue..."
                ;;
            6)
                echo ""
                print_info "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid choice. Please enter 1-6."
                sleep 2
                ;;
        esac
    done
}

# Main script
main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_warning "This script may require root privileges for ZFS operations"
    fi

    # Parse command line arguments
    case "${1:-}" in
        "list"|"-l")
            list_pending_transactions
            ;;
        "show"|"-s")
            if [[ -z "$2" ]]; then
                print_error "Transaction ID required"
                echo "Usage: $0 show <transaction_id>"
                exit 1
            fi
            show_transaction_details "$2"
            ;;
        "rollback"|"-r")
            if [[ -z "$2" ]]; then
                print_error "Transaction ID required"
                echo "Usage: $0 rollback <transaction_id>"
                exit 1
            fi
            rollback_transaction "$2"
            ;;
        "recover"|"-a")
            recover_all_transactions
            ;;
        "cleanup"|"-c")
            cleanup_old_transactions "${2:-30}"
            ;;
        "help"|"-h"|"--help")
            print_header
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  list             List all pending transactions"
            echo "  show <tx_id>     Show details for specific transaction"
            echo "  rollback <tx_id> Rollback specific transaction"
            echo "  recover          Recover all pending transactions automatically"
            echo "  cleanup [days]   Cleanup transactions older than days (default: 30)"
            echo "  help             Show this help message"
            echo ""
            echo "If no command is provided, interactive mode will start."
            echo ""
            ;;
        "")
            # No arguments - start interactive mode
            interactive_mode
            ;;
        *)
            print_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"
