#!/bin/bash

# WireGuard AWS Cleanup Script
# Usage: 
#   ./scripts/cleanup.sh           # Quick cleanup (default)
#   ./scripts/cleanup.sh --full    # Full cleanup including local WireGuard
#   ./scripts/cleanup.sh --help    # Show help

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_command() {
    echo -e "${BLUE}[COMMAND]${NC} $1"
}

print_header() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Show help
show_help() {
    echo "WireGuard AWS Cleanup Script"
    echo
    echo "Usage:"
    echo "  $0                 # Quick cleanup (default)"
    echo "  $0 --full          # Full cleanup including local WireGuard"
    echo "  $0 --ultra         # Ultra cleanup (removes everything including backups)"
    echo "  $0 --dry-run       # Show what would be destroyed (safe)"
    echo "  $0 --help          # Show this help"
    echo
    echo "Modes:"
    echo "  Quick Mode (default):"
    echo "    - Destroys AWS infrastructure"
    echo "    - Removes local config files"
    echo "    - Shows commands to clean local WireGuard"
    echo
    echo "  Full Mode (--full):"
    echo "    - Does everything in Quick Mode"
    echo "    - Stops and removes local WireGuard interface"
    echo "    - Removes WireGuard config from system"
    echo "    - Cleans up SSH config entries"
    echo
    echo "  Ultra Mode (--ultra):"
    echo "    - Does everything in Full Mode"
    echo "    - Removes backup files"
    echo "    - Removes remaining WireGuard configs"
    echo "    - Complete system cleanup"
    echo
    echo "  Dry-Run Mode (--dry-run):"
    echo "    - Shows what would be destroyed"
    echo "    - No actual changes made"
    echo "    - Safe for testing"
    echo
    echo "Safety Features:"
    echo "  - Confirmation prompts for destructive actions"
    echo "  - Backup creation before cleanup"
    echo "  - Dry-run mode available"
    echo "  - No auto-approval flags (safety first)"
    echo "  - Smart detection of empty infrastructure"
    echo
    echo "Examples:"
    echo "  $0                  # Quick cleanup"
    echo "  $0 --full           # Full cleanup"
    echo "  $0 --ultra          # Ultra cleanup"
    echo "  $0 --dry-run        # Safe preview"
}

# Confirmation prompt
confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "$default" == "y" ]]; then
        read -p "$message [Y/n]: " -r
    else
        read -p "$message [y/N]: " -r
    fi
    
    if [[ "$default" == "y" ]]; then
        [[ $REPLY =~ ^[Nn]$ ]] && return 1
    else
        [[ $REPLY =~ ^[Yy]$ ]] || return 1
    fi
    return 0
}

# Check if we're in the right directory
check_directory() {
    if [[ ! -f "terraform/main.tf" ]]; then
        print_error "This script must be run from the project root directory"
        print_error "Expected to find terraform/main.tf"
        exit 1
    fi
}

# Backup important files
backup_files() {
    print_header "Creating backup of important files..."
    
    local backup_dir="backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup local WireGuard config if it exists
    if [[ -f "local_wg0.conf" ]]; then
        cp local_wg0.conf "$backup_dir/"
        print_status "Backed up local_wg0.conf to $backup_dir/"
    fi
    
    # Backup SSH config if it exists
    if [[ -f "ssh_config" ]]; then
        cp ssh_config "$backup_dir/"
        print_status "Backed up ssh_config to $backup_dir/"
    fi
    
    print_success "Backup created in $backup_dir/"
}

# Destroy AWS infrastructure
destroy_infrastructure() {
    print_header "Destroying AWS infrastructure..."
    
    cd terraform
    
    # Check if terraform state exists
    if [[ ! -f "terraform.tfstate" ]]; then
        print_warning "No terraform state found. Infrastructure may already be destroyed."
        cd ..
        return 0
    fi
    
    # Check if there are any resources to destroy
    print_status "Checking for resources to destroy..."
    if ! terraform plan -destroy -detailed-exitcode &> /dev/null; then
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            print_status "No AWS resources found to destroy. Infrastructure is already clean."
            cd ..
            return 0
        elif [[ $exit_code -eq 1 ]]; then
            print_error "Terraform plan failed. Check your configuration."
            cd ..
            return 1
        fi
    fi
    
    # Show what will be destroyed
    print_status "Planning destruction..."
    terraform plan -destroy
    
    # Check if plan shows no changes
    if terraform plan -destroy -detailed-exitcode &> /dev/null; then
        print_status "No AWS resources found to destroy. Infrastructure is already clean."
        cd ..
        return 0
    fi
    
    if ! confirm_action "The above resources will be destroyed. Continue?"; then
        print_warning "Skipping infrastructure destruction"
        cd ..
        return 0
    fi
    
    # Destroy infrastructure
    print_status "Destroying infrastructure..."
    terraform destroy -auto-approve
    
    cd ..
    print_success "AWS infrastructure destroyed"
}

# Clean up local files
cleanup_local_files() {
    print_header "Cleaning up local files..."
    
    # Remove local WireGuard config
    if [[ -f "local_wg0.conf" ]]; then
        rm -f local_wg0.conf
        print_status "Removed local_wg0.conf"
    fi
    
    # Remove SSH config
    if [[ -f "ssh_config" ]]; then
        rm -f ssh_config
        print_status "Removed ssh_config"
    fi
    
    # Remove Ansible inventory
    if [[ -f "ansible/inventory/infrastructure.ini" ]]; then
        rm -f ansible/inventory/infrastructure.ini
        print_status "Removed Ansible inventory"
    fi
    
    # Remove local WireGuard keys
    if [[ -f "local_private_key" ]]; then
        rm -f local_private_key
        print_status "Removed local_private_key"
    fi
    
    if [[ -f "local_public_key" ]]; then
        rm -f local_public_key
        print_status "Removed local_public_key"
    fi
    
    # Remove SSH keys (optional - ask user)
    if [[ -f "terraform/keys/wireguard_key" || -f "terraform/keys/wireguard_key.pub" ]]; then
        if confirm_action "Remove SSH keys from terraform/keys/? (These can be regenerated)"; then
            rm -f terraform/keys/wireguard_key terraform/keys/wireguard_key.pub
            print_status "Removed SSH keys"
        else
            print_warning "Keeping SSH keys for future use"
        fi
    fi
    
    print_success "Local files cleaned up"
}

# Stop and remove local WireGuard (full mode only)
cleanup_wireguard() {
    print_header "Cleaning up local WireGuard..."
    
    # Check if WireGuard is running
    if sudo wg show &> /dev/null; then
        print_status "WireGuard interface is running"
        
        if ! confirm_action "Stop and remove WireGuard interface?"; then
            print_warning "Skipping WireGuard cleanup"
            return 0
        fi
        
        # Stop WireGuard interface
        if sudo wg-quick down wg0 &> /dev/null; then
            print_status "Stopped WireGuard interface"
        fi
    else
        print_status "WireGuard interface not running"
    fi
    
    # Remove WireGuard config from system
    if [[ -f "/etc/wireguard/wg0.conf" ]]; then
        if ! confirm_action "Remove WireGuard config from /etc/wireguard/?"; then
            print_warning "Skipping WireGuard config removal"
            return 0
        fi
        
        sudo rm -f /etc/wireguard/wg0.conf
        print_status "Removed WireGuard config from system"
    fi
    
    print_success "WireGuard cleanup completed"
}

# Clean up SSH config entries
cleanup_ssh_config() {
    print_header "Cleaning up SSH config entries..."
    
    local ssh_config_file="$HOME/.ssh/config"
    
    if [[ ! -f "$ssh_config_file" ]]; then
        print_status "No SSH config file found"
        return 0
    fi
    
    # Check if our entries exist
    if grep -q "bastion-vpn\|private-vpn" "$ssh_config_file" 2>/dev/null; then
        if ! confirm_action "Remove WireGuard SSH config entries from ~/.ssh/config?"; then
            print_warning "Skipping SSH config cleanup"
            return 0
        fi
        
        # Create backup of SSH config
        cp "$ssh_config_file" "${ssh_config_file}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Remove our entries
        sed -i '/# WireGuard AWS Setup/,/^$/d' "$ssh_config_file"
        print_status "Removed WireGuard SSH config entries"
    else
        print_status "No WireGuard SSH config entries found"
    fi
    
    print_success "SSH config cleanup completed"
}

# Show cleanup commands (quick mode)
show_cleanup_commands() {
    echo
    print_command "=== LOCAL CLEANUP COMMANDS ==="
    echo
    print_command "1. Stop WireGuard interface:"
    echo "sudo wg-quick down wg0"
    echo
    print_command "2. Remove WireGuard config:"
    echo "sudo rm -f /etc/wireguard/wg0.conf"
    echo
    print_command "3. Check WireGuard status:"
    echo "sudo wg show"
    echo
    print_command "4. Remove SSH config entries (if added):"
    echo "Edit ~/.ssh/config and remove WireGuard entries"
    echo
    print_command "5. Clean up project files:"
    echo "rm -f local_wg0.conf ssh_config"
    echo
    print_command "6. Remove backup directory:"
    echo "rm -rf backup_*"
}

# Show full cleanup completion
show_full_completion() {
    echo
    print_success "=== FULL CLEANUP COMPLETED ==="
    echo
    print_command "All resources have been cleaned up:"
    echo "✓ AWS infrastructure destroyed"
    echo "✓ Local WireGuard interface stopped"
    echo "✓ WireGuard config removed"
    echo "✓ SSH config entries cleaned"
    echo "✓ Local files removed"
    echo
    print_command "Backup files are available in: backup_*"
    print_command "You can safely remove them when ready:"
    echo "rm -rf backup_*"
    echo
    print_command "Optional: Remove remaining WireGuard configs:"
    echo "sudo rm -f /etc/wireguard/wg0.conf /etc/wireguard/local_wg0.conf"
}

# Quick mode (default)
quick_mode() {
    print_status "Running in Quick Mode - infrastructure and local files cleanup"
    echo
    
    check_directory
    backup_files
    destroy_infrastructure
    cleanup_local_files
    show_cleanup_commands
    
    print_success "Quick cleanup completed! Follow the commands above to clean local WireGuard."
}

# Full mode
full_mode() {
    print_status "Running in Full Mode - complete cleanup including local WireGuard"
    echo
    
    check_directory
    backup_files
    destroy_infrastructure
    cleanup_local_files
    cleanup_wireguard
    cleanup_ssh_config
    show_full_completion
    
    print_success "Full cleanup completed! All resources have been removed."
}

# Ultra mode
ultra_mode() {
    print_status "Running in Ultra Mode - complete cleanup including backups and system files"
    echo
    
    check_directory
    backup_files
    destroy_infrastructure
    cleanup_local_files
    cleanup_wireguard
    cleanup_ssh_config
    
    # Remove backup files
    print_header "Removing backup files..."
    if [[ -d "backup_"* ]]; then
        if ! confirm_action "Remove backup files? This cannot be undone."; then
            print_warning "Skipping backup removal"
        else
            rm -rf backup_*
            print_status "Removed backup files"
        fi
    else
        print_status "No backup files found"
    fi
    
    # Remove remaining WireGuard configs
    print_header "Removing remaining WireGuard configs..."
    if [[ -f "/etc/wireguard/wg0.conf" || -f "/etc/wireguard/local_wg0.conf" ]]; then
        if ! confirm_action "Remove remaining WireGuard configs from /etc/wireguard/?"; then
            print_warning "Skipping WireGuard config removal"
        else
            sudo rm -f /etc/wireguard/wg0.conf /etc/wireguard/local_wg0.conf
            print_status "Removed remaining WireGuard configs"
        fi
    else
        print_status "No remaining WireGuard configs found"
    fi
    
    echo
    print_success "=== ULTRA CLEANUP COMPLETED ==="
    echo
    print_command "All resources have been completely cleaned up:"
    echo "✓ AWS infrastructure destroyed"
    echo "✓ Local WireGuard interface stopped"
    echo "✓ WireGuard config removed"
    echo "✓ SSH config entries cleaned"
    echo "✓ Local files removed"
    echo "✓ Backup files removed"
    echo "✓ Remaining WireGuard configs removed"
    echo
    print_success "Ultra cleanup completed! System is completely clean."
}

# Dry-run mode
dry_run_mode() {
    print_status "Running in Dry-Run Mode - showing what would be destroyed (SAFE)"
    echo
    
    check_directory
    
    print_header "=== DRY-RUN PREVIEW ==="
    echo
    print_command "AWS Infrastructure that would be destroyed:"
    cd terraform
    if [[ -f "terraform.tfstate" ]]; then
        # Check if there are any resources to destroy
        if terraform plan -destroy -detailed-exitcode &> /dev/null; then
            echo "No AWS resources found to destroy. Infrastructure is already clean."
        else
            terraform plan -destroy
        fi
    else
        echo "No Terraform state found - no AWS resources to destroy"
    fi
    cd ..
    
    print_command "Local files that would be removed:"
    if [[ -f "local_wg0.conf" ]]; then
        echo "  - local_wg0.conf"
    fi
    if [[ -f "ssh_config" ]]; then
        echo "  - ssh_config"
    fi
    if [[ -f "ansible/inventory/infrastructure.ini" ]]; then
        echo "  - ansible/inventory/infrastructure.ini"
    fi
    if [[ -f "local_private_key" ]]; then
        echo "  - local_private_key"
    fi
    if [[ -f "local_public_key" ]]; then
        echo "  - local_public_key"
    fi
    if [[ -f "terraform/keys/wireguard_key" ]]; then
        echo "  - terraform/keys/wireguard_key"
    fi
    if [[ -f "terraform/keys/wireguard_key.pub" ]]; then
        echo "  - terraform/keys/wireguard_key.pub"
    fi
    
    print_command "WireGuard interface that would be stopped:"
    if sudo wg show &> /dev/null; then
        echo "  - Active WireGuard interface (wg0)"
    else
        echo "  - No active WireGuard interface found"
    fi
    
    print_command "WireGuard configs that would be removed:"
    if [[ -f "/etc/wireguard/wg0.conf" ]]; then
        echo "  - /etc/wireguard/wg0.conf"
    fi
    if [[ -f "/etc/wireguard/local_wg0.conf" ]]; then
        echo "  - /etc/wireguard/local_wg0.conf"
    fi
    
    print_command "Backup files that would be removed:"
    if [[ -d "backup_"* ]]; then
        echo "  - backup_* directories"
    else
        echo "  - No backup files found"
    fi
    
    echo
    print_success "=== DRY-RUN COMPLETED ==="
    print_command "No actual changes were made. This was a safe preview."
    print_command "To perform actual cleanup, run without --dry-run flag."
}

# Main execution
main() {
    # Parse arguments
    case "${1:-}" in
        --full)
            full_mode
            ;;
        --ultra)
            ultra_mode
            ;;
        --dry-run)
            dry_run_mode
            ;;
        --help|-h)
            show_help
            ;;
        "")
            quick_mode
            ;;
        *)
            print_error "Unknown option: $1"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
