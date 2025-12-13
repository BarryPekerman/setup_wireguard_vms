#!/bin/bash

# WireGuard AWS Cleanup Script
# Usage: 
#   ./scripts/cleanup.sh           # Quick cleanup (default)
#   ./scripts/cleanup.sh --full    # Full cleanup including local WireGuard
#   ./scripts/cleanup.sh -v        # Verbose output (show terraform details)
#   ./scripts/cleanup.sh --help    # Show help

set -euo pipefail

# Global flags
VERBOSE=false

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
    echo "  $0                      # Quick cleanup (default)"
    echo "  $0 --full               # Full cleanup including local WireGuard"
    echo "  $0 --dry-run            # Show what would be destroyed (safe)"
    echo "  $0 --help               # Show this help"
    echo
    echo "Flags (can combine with modes):"
    echo "  -v, --verbose           # Show detailed terraform output"
    echo "  --check-orphans         # Check for orphaned AWS resources only"
    echo
    echo "Modes:"
    echo "  Quick Mode (default):"
    echo "    - Destroys AWS infrastructure via Terraform"
    echo "    - Removes local config files"
    echo "    - Stops WireGuard interface created by this project"
    echo
    echo "  Full Mode (--full):"
    echo "    - Does everything in Quick Mode"
    echo "    - Cleans up SSH known_hosts entries"
    echo "    - More thorough local cleanup"
    echo
    echo "  Dry-Run Mode (--dry-run):"
    echo "    - Shows what would be destroyed"
    echo "    - No actual changes made"
    echo "    - Safe for testing"
    echo
    echo "Examples:"
    echo "  $0 -v                   # Verbose cleanup"
    echo "  $0 --full -v            # Full cleanup with verbose output"
    echo "  $0 --check-orphans      # Just check for orphaned resources"
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
    
    # terraform plan -detailed-exitcode returns:
    # 0 = Success, no changes (infrastructure clean)
    # 1 = Error (configuration problem)
    # 2 = Success, changes present (resources to destroy)
    # Capture exit code without letting set -e kill the script
    local exit_code=0
    if [[ "$VERBOSE" == "true" ]]; then
        terraform plan -destroy -detailed-exitcode || exit_code=$?
        echo ""
        print_status "Terraform plan exit code: $exit_code (0=clean, 1=error, 2=resources to destroy)"
    else
        terraform plan -destroy -detailed-exitcode &>/dev/null || exit_code=$?
    fi
    
    if [[ $exit_code -eq 0 ]]; then
        print_status "No AWS resources found to destroy. Infrastructure is already clean."
        cd ..
        return 0
    elif [[ $exit_code -eq 1 ]]; then
        print_error "Terraform plan failed. Run with -v for details."
        print_warning "Attempting destroy anyway..."
        # Don't return - try to destroy what we can
    fi
    # exit_code 2 means there ARE resources to destroy - continue
    
    # Show what will be destroyed (summary only unless verbose)
    local resource_count
    resource_count=$(terraform state list 2>/dev/null | wc -l || echo "0")
    print_status "Found $resource_count resources to destroy"
    
    if [[ "$VERBOSE" == "true" ]]; then
        print_status "Planning destruction..."
        terraform plan -destroy
    fi
    
    # Destroy infrastructure with retry logic (AWS can have transient failures)
    local max_attempts=3
    local attempt=1
    local destroy_success=false
    
    while [[ $attempt -le $max_attempts ]]; do
        print_status "Destroying infrastructure (attempt $attempt/$max_attempts)..."
        
        if terraform destroy -auto-approve; then
            destroy_success=true
            break
        else
            if [[ $attempt -lt $max_attempts ]]; then
                print_warning "Destroy failed, retrying in 10 seconds..."
                sleep 10
            fi
        fi
        ((attempt++))
    done
    
    cd ..
    
    if [[ "$destroy_success" == "true" ]]; then
        print_success "AWS infrastructure destroyed"
    else
        print_error "Failed to destroy infrastructure after $max_attempts attempts"
        print_warning "Some resources may still exist. Check AWS Console or run: ./scripts/cleanup.sh --check-orphans"
        return 1
    fi
    
    # Now that terraform destroy is complete, clean up SSH keys
    print_status "Cleaning up SSH keys after infrastructure destruction..."
    cleanup_project_ssh_keys
    
    # Clean up any orphaned AWS key pairs (not tracked by Terraform)
    cleanup_orphaned_aws_keypairs
    
    # Clean up orphaned AWS resources by tag (catches resources Terraform forgot)
    cleanup_orphaned_aws_resources
}

# Clean up orphaned AWS resources by tag (not tracked by Terraform state)
cleanup_orphaned_aws_resources() {
    print_header "Checking for orphaned AWS resources (by tag)..."
    
    if ! command -v aws &> /dev/null; then
        print_warning "AWS CLI not available, skipping orphaned resource cleanup"
        return 0
    fi
    
    local project_name="wireguard-setup"
    local found_orphans=false
    
    # 1. Check for orphaned EC2 instances
    print_status "Checking for orphaned EC2 instances..."
    local orphan_instances
    orphan_instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=${project_name}-*" "Name=instance-state-name,Values=running,stopped,pending" \
        --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$orphan_instances" ]]; then
        found_orphans=true
        print_warning "Found orphaned EC2 instances:"
        echo "$orphan_instances" | while read -r line; do
            echo "  - $line"
        done
    fi
    
    # 2. Check for orphaned NAT Gateways (these cost money!)
    print_status "Checking for orphaned NAT Gateways..."
    local orphan_nats
    orphan_nats=$(aws ec2 describe-nat-gateways \
        --filter "Name=tag:Name,Values=${project_name}-*" "Name=state,Values=available,pending" \
        --query 'NatGateways[*].[NatGatewayId,State]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$orphan_nats" ]]; then
        found_orphans=true
        print_warning "Found orphaned NAT Gateways (💸 these cost ~\$1.08/day each!):"
        echo "$orphan_nats" | while read -r line; do
            echo "  - $line"
        done
    fi
    
    # 3. Check for orphaned Elastic IPs
    print_status "Checking for orphaned Elastic IPs..."
    local orphan_eips
    orphan_eips=$(aws ec2 describe-addresses \
        --filters "Name=tag:Name,Values=${project_name}-*" \
        --query 'Addresses[*].[AllocationId,PublicIp]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$orphan_eips" ]]; then
        found_orphans=true
        print_warning "Found orphaned Elastic IPs:"
        echo "$orphan_eips" | while read -r line; do
            echo "  - $line"
        done
    fi
    
    # 4. Check for orphaned VPCs
    print_status "Checking for orphaned VPCs..."
    local orphan_vpcs
    orphan_vpcs=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=${project_name}-*" \
        --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0]]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$orphan_vpcs" ]]; then
        found_orphans=true
        print_warning "Found orphaned VPCs:"
        echo "$orphan_vpcs" | while read -r line; do
            echo "  - $line"
        done
    fi
    
    # 5. Check for orphaned Security Groups
    print_status "Checking for orphaned Security Groups..."
    local orphan_sgs
    orphan_sgs=$(aws ec2 describe-security-groups \
        --filters "Name=tag:Name,Values=${project_name}-*" \
        --query 'SecurityGroups[*].[GroupId,GroupName]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$orphan_sgs" ]]; then
        found_orphans=true
        print_warning "Found orphaned Security Groups:"
        echo "$orphan_sgs" | while read -r line; do
            echo "  - $line"
        done
    fi
    
    # 6. Check for orphaned Key Pairs
    print_status "Checking for orphaned Key Pairs..."
    local orphan_keys
    orphan_keys=$(aws ec2 describe-key-pairs \
        --filters "Name=key-name,Values=${project_name}-*" \
        --query 'KeyPairs[*].[KeyName,KeyPairId]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$orphan_keys" ]]; then
        found_orphans=true
        print_warning "Found orphaned Key Pairs:"
        echo "$orphan_keys" | while read -r line; do
            echo "  - $line"
        done
    fi
    
    if [[ "$found_orphans" == "false" ]]; then
        print_success "No orphaned AWS resources found"
        return 0
    fi
    
    echo
    print_warning "⚠️  Orphaned resources found! These are NOT tracked by Terraform."
    print_warning "They may be left over from previous failed deployments."
    echo
    
    if ! confirm_action "Delete ALL orphaned AWS resources listed above?"; then
        print_warning "Skipping orphaned resource cleanup"
        print_warning "You can manually delete them in AWS Console or run this script again"
        return 0
    fi
    
    # Delete orphaned resources in correct order
    print_status "Deleting orphaned resources..."
    
    # 1. Terminate EC2 instances first
    if [[ -n "$orphan_instances" ]]; then
        local instance_ids
        instance_ids=$(echo "$orphan_instances" | awk '{print $1}' | tr '\n' ' ')
        print_status "Terminating EC2 instances: $instance_ids"
        aws ec2 terminate-instances --instance-ids $instance_ids 2>/dev/null || true
        print_status "Waiting for instances to terminate..."
        aws ec2 wait instance-terminated --instance-ids $instance_ids 2>/dev/null || true
    fi
    
    # 2. Delete NAT Gateways
    if [[ -n "$orphan_nats" ]]; then
        echo "$orphan_nats" | while read -r nat_id state; do
            print_status "Deleting NAT Gateway: $nat_id"
            aws ec2 delete-nat-gateway --nat-gateway-id "$nat_id" 2>/dev/null || true
        done
        print_status "Waiting for NAT Gateways to delete (this takes ~1-2 minutes)..."
        sleep 60
    fi
    
    # 3. Release Elastic IPs
    if [[ -n "$orphan_eips" ]]; then
        echo "$orphan_eips" | while read -r alloc_id public_ip; do
            print_status "Releasing Elastic IP: $public_ip ($alloc_id)"
            aws ec2 release-address --allocation-id "$alloc_id" 2>/dev/null || true
        done
    fi
    
    # 4. Delete Security Groups (before VPCs)
    if [[ -n "$orphan_sgs" ]]; then
        echo "$orphan_sgs" | while read -r sg_id sg_name; do
            print_status "Deleting Security Group: $sg_name ($sg_id)"
            aws ec2 delete-security-group --group-id "$sg_id" 2>/dev/null || true
        done
    fi
    
    # 5. Delete VPCs (and their dependencies)
    if [[ -n "$orphan_vpcs" ]]; then
        echo "$orphan_vpcs" | while read -r vpc_id vpc_name; do
            print_status "Cleaning up VPC: $vpc_name ($vpc_id)"
            
            # Detach and delete internet gateways
            for igw in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --query 'InternetGateways[*].InternetGatewayId' --output text 2>/dev/null); do
                print_status "  Detaching Internet Gateway: $igw"
                aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc_id" 2>/dev/null || true
                aws ec2 delete-internet-gateway --internet-gateway-id "$igw" 2>/dev/null || true
            done
            
            # Delete subnets
            for subnet in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[*].SubnetId' --output text 2>/dev/null); do
                print_status "  Deleting Subnet: $subnet"
                aws ec2 delete-subnet --subnet-id "$subnet" 2>/dev/null || true
            done
            
            # Delete route tables (except main)
            for rt in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" "Name=association.main,Values=false" --query 'RouteTables[*].RouteTableId' --output text 2>/dev/null); do
                print_status "  Deleting Route Table: $rt"
                aws ec2 delete-route-table --route-table-id "$rt" 2>/dev/null || true
            done
            
            # Delete remaining security groups in this VPC
            for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null); do
                print_status "  Deleting Security Group: $sg"
                aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
            done
            
            # Delete VPC
            print_status "  Deleting VPC: $vpc_id"
            aws ec2 delete-vpc --vpc-id "$vpc_id" 2>/dev/null || true
        done
    fi
    
    # 6. Delete Key Pairs
    if [[ -n "$orphan_keys" ]]; then
        echo "$orphan_keys" | while read -r key_name key_id; do
            print_status "Deleting Key Pair: $key_name"
            aws ec2 delete-key-pair --key-name "$key_name" 2>/dev/null || true
        done
    fi
    
    print_success "Orphaned AWS resource cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    print_header "Cleaning up local files..."
    
    # Note: SSH keys are cleaned up in destroy_infrastructure() after terraform destroy
    
    # Remove local WireGuard configs (wg0, wg1, wg2, etc.)
    for conf in local_wg*.conf; do
        if [[ -f "$conf" ]]; then
            rm -f "$conf"
            print_status "Removed $conf"
        fi
    done
    
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

# Stop and remove local WireGuard - ONLY the interface this project created
cleanup_wireguard() {
    print_header "Cleaning up local WireGuard..."
    
    # Check if we have saved state from wireguard_client.sh
    local our_interface=""
    local our_endpoint=""
    
    if [[ -f ".wireguard_interface" ]]; then
        our_interface=$(cat .wireguard_interface)
        print_status "This project created interface: $our_interface"
    fi
    
    if [[ -f ".wireguard_endpoint" ]]; then
        our_endpoint=$(cat .wireguard_endpoint)
        print_status "This project's endpoint: $our_endpoint"
    fi
    
    # If we know which interface we created, stop ONLY that one
    if [[ -n "$our_interface" ]]; then
        # Check if it's running
        if ip link show "$our_interface" &>/dev/null; then
            print_status "Stopping WireGuard interface: $our_interface"
            if sudo wg-quick down "$our_interface" 2>/dev/null; then
                print_success "Stopped: $our_interface"
            else
                print_warning "Could not stop $our_interface (may already be down)"
            fi
        else
            print_status "Interface $our_interface is not running"
        fi
        
        # Remove the system config for this interface
        if [[ -f "/etc/wireguard/${our_interface}.conf" ]]; then
            sudo rm -f "/etc/wireguard/${our_interface}.conf"
            print_status "Removed /etc/wireguard/${our_interface}.conf"
        fi
        
        # Clean up state files
        rm -f .wireguard_interface .wireguard_endpoint
        print_status "Cleaned up state files"
    else
        # No saved state - try to find interfaces pointing to our current bastion
        print_warning "No saved interface state found."
        print_status "Looking for interfaces pointing to our infrastructure..."
        
        # Get current bastion IP from terraform if available
        local current_bastion=""
        if [[ -f "terraform/terraform.tfstate" ]]; then
            current_bastion=$(cd terraform && terraform output -raw bastion_public_ip 2>/dev/null || echo "")
        fi
        
        if [[ -n "$current_bastion" ]]; then
            # Find local configs pointing to this bastion
            for conf in local_wg*.conf; do
                if [[ -f "$conf" ]] && grep -q "$current_bastion" "$conf" 2>/dev/null; then
                    local iface_name
                    iface_name=$(basename "$conf" .conf | sed 's/local_//')
                    print_status "Found config pointing to current bastion: $conf (interface: $iface_name)"
                    
                    if ip link show "$iface_name" &>/dev/null; then
                        if confirm_action "Stop interface $iface_name?"; then
                            sudo wg-quick down "$iface_name" 2>/dev/null || true
                            print_success "Stopped: $iface_name"
                        fi
                    fi
                    
                    if [[ -f "/etc/wireguard/${iface_name}.conf" ]]; then
                        sudo rm -f "/etc/wireguard/${iface_name}.conf"
                        print_status "Removed /etc/wireguard/${iface_name}.conf"
                    fi
                fi
            done
        else
            print_warning "Could not determine current bastion IP."
            print_warning "Manual cleanup may be needed: sudo wg-quick down <interface>"
        fi
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

# Clean up SSH known_hosts entries for WireGuard IPs and bastion
cleanup_ssh_known_hosts() {
    print_header "Cleaning up SSH known_hosts entries..."
    
    local known_hosts="$HOME/.ssh/known_hosts"
    
    if [[ ! -f "$known_hosts" ]]; then
        print_status "No known_hosts file found"
        return 0
    fi
    
    # WireGuard VPN IPs that get reused across deployments
    local wg_ips=("10.0.3.1" "10.0.3.2" "10.0.3.3")
    local entries_found=false
    
    # Check for WireGuard IPs
    for ip in "${wg_ips[@]}"; do
        if grep -q "^${ip}[, ]" "$known_hosts" 2>/dev/null; then
            entries_found=true
            break
        fi
    done
    
    # Also check for bastion public IP from Terraform state
    local bastion_ip=""
    if [[ -f "terraform/terraform.tfstate" ]]; then
        bastion_ip=$(cd terraform && terraform output -raw bastion_public_ip 2>/dev/null || echo "")
    fi
    
    if [[ -n "$bastion_ip" ]] && grep -q "^${bastion_ip}[, ]" "$known_hosts" 2>/dev/null; then
        entries_found=true
    fi
    
    if [[ "$entries_found" == "false" ]]; then
        print_status "No WireGuard-related known_hosts entries found"
        return 0
    fi
    
    print_status "Found SSH known_hosts entries for WireGuard IPs"
    
    if ! confirm_action "Remove known_hosts entries for WireGuard IPs? (Prevents host key errors on next deploy)"; then
        print_warning "Skipping known_hosts cleanup"
        print_warning "You may see 'HOST KEY CHANGED' warnings on next deployment"
        return 0
    fi
    
    # Remove WireGuard VPN IPs
    for ip in "${wg_ips[@]}"; do
        if grep -q "^${ip}[, ]" "$known_hosts" 2>/dev/null; then
            ssh-keygen -f "$known_hosts" -R "$ip" 2>/dev/null
            print_status "Removed known_hosts entry for $ip"
        fi
    done
    
    # Remove bastion public IP
    if [[ -n "$bastion_ip" ]]; then
        if grep -q "^${bastion_ip}[, ]" "$known_hosts" 2>/dev/null; then
            ssh-keygen -f "$known_hosts" -R "$bastion_ip" 2>/dev/null
            print_status "Removed known_hosts entry for bastion ($bastion_ip)"
        fi
    fi
    
    print_success "SSH known_hosts cleanup completed"
}

# Show cleanup commands (quick mode)
show_cleanup_commands() {
    echo
    print_command "=== LOCAL CLEANUP COMMANDS ==="
    echo
    print_command "1. Stop WireGuard interface(s):"
    echo "# Check which interfaces exist first:"
    echo "ip link show type wireguard"
    echo "# Then stop them (replace wgX with actual interface name):"
    echo "sudo wg-quick down wg0   # or wg1, wg2, etc."
    echo
    print_command "2. Remove WireGuard config(s):"
    echo "sudo rm -f /etc/wireguard/wg*.conf"
    echo
    print_command "3. Check WireGuard status:"
    echo "sudo wg show"
    echo
    print_command "4. Remove SSH config entries (if added):"
    echo "Edit ~/.ssh/config and remove WireGuard entries"
    echo
    print_command "5. Clean up project files:"
    echo "rm -f local_wg*.conf ssh_config"
    echo
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
    echo "✓ SSH known_hosts entries removed (no more host key warnings!)"
    echo "✓ Local files removed"
    echo
    echo
    print_command "Optional: Remove remaining WireGuard configs:"
    echo "sudo rm -f /etc/wireguard/wg*.conf"
}

# Quick mode (default) - now includes WireGuard cleanup
quick_mode() {
    print_status "Running cleanup - infrastructure, local files, and WireGuard interface"
    echo
    
    check_directory
    destroy_infrastructure
    cleanup_local_files
    cleanup_wireguard  # Now smart enough to only stop OUR interface
    cleanup_ssh_known_hosts  # Remove known_hosts for VPN IPs (prevents host key warnings on redeploy)
    
    print_success "Cleanup completed!"
}

# Full mode
full_mode() {
    print_status "Running in Full Mode - complete cleanup including local WireGuard"
    echo
    
    check_directory
    destroy_infrastructure
    cleanup_local_files
    cleanup_wireguard
    cleanup_ssh_config
    cleanup_ssh_known_hosts
    show_full_completion
    
    print_success "Full cleanup completed! All resources have been removed."
}

# Ultra mode
ultra_mode() {
    print_status "Running in Ultra Mode - complete cleanup including system files"
    echo
    
    check_directory
    destroy_infrastructure
    cleanup_local_files
    cleanup_wireguard
    cleanup_ssh_config
    cleanup_ssh_known_hosts
    
    
    # Remove ONLY WireGuard configs that belong to THIS project
    print_header "Checking for remaining project WireGuard configs..."
    
    # Only remove configs that we can verify belong to this project
    # by checking if they point to our bastion IP
    local current_bastion=""
    if [[ -f "terraform/terraform.tfstate" ]]; then
        current_bastion=$(cd terraform && terraform output -raw bastion_public_ip 2>/dev/null || echo "")
    fi
    
    local removed_any=false
    for conf in local_wg*.conf; do
        if [[ -f "$conf" ]]; then
            local iface_name
            iface_name=$(basename "$conf" .conf | sed 's/local_//')
            local system_conf="/etc/wireguard/${iface_name}.conf"
            
            # Only remove system config if our local config exists AND matches bastion
            if [[ -f "$system_conf" ]]; then
                if [[ -n "$current_bastion" ]] && grep -q "$current_bastion" "$conf" 2>/dev/null; then
                    print_status "Removing project config: $system_conf (points to $current_bastion)"
                    sudo rm -f "$system_conf"
                    removed_any=true
                else
                    print_status "Skipping $system_conf (does not match current infrastructure)"
                fi
            fi
        fi
    done
    
    if [[ "$removed_any" == "false" ]]; then
        print_status "No project-specific WireGuard configs found to remove"
    fi
    
    print_warning "Note: Other WireGuard configs (e.g., wg0 from other projects) are NOT touched"
    
    echo
    print_success "=== CLEANUP COMPLETED ==="
    echo
    print_command "Project resources have been cleaned up:"
    echo "✓ AWS infrastructure destroyed"
    echo "✓ Project WireGuard interface stopped"
    echo "✓ Project WireGuard configs removed"
    echo "✓ SSH config entries cleaned"
    echo "✓ Local files removed"
    echo ""
    echo "Note: Other WireGuard interfaces (e.g., wg0) were NOT touched"
    echo
    print_success "Cleanup completed!"
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
        # terraform plan -detailed-exitcode: 0=no changes, 1=error, 2=changes present
        # Capture exit code without letting set -e kill the script
        local exit_code=0
        terraform plan -destroy -detailed-exitcode &> /dev/null || exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            echo "No AWS resources found to destroy. Infrastructure is already clean."
        else
            terraform plan -destroy
        fi
    else
        echo "No Terraform state found - no AWS resources to destroy"
    fi
    cd ..
    
    print_command "Local files that would be removed:"
    for conf in local_wg*.conf; do
        if [[ -f "$conf" ]]; then
            echo "  - $conf"
        fi
    done
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
    
    print_command "WireGuard interfaces that would be stopped:"
    local active_wg
    active_wg=$(ip link show type wireguard 2>/dev/null | grep -oP '^\d+:\s+\Kwg\d+' || true)
    if [[ -n "$active_wg" ]]; then
        echo "$active_wg" | while read -r iface; do
            echo "  - $iface"
        done
    else
        echo "  - No active WireGuard interfaces found"
    fi
    
    print_command "WireGuard configs that would be removed:"
    local wg_conf_found=false
    for conf in /etc/wireguard/wg*.conf /etc/wireguard/local_wg*.conf; do
        if [[ -f "$conf" ]]; then
            echo "  - $conf"
            wg_conf_found=true
        fi
    done
    if [[ "$wg_conf_found" == "false" ]]; then
        echo "  - No WireGuard configs found"
    fi
    
    print_command "SSH keys that would be removed:"
    local ssh_keys_found=false
    for key_file in ~/.ssh/wireguard-*; do
        if [[ -f "$key_file" ]]; then
            echo "  - $key_file"
            ssh_keys_found=true
        fi
    done
    if [[ "$ssh_keys_found" == "false" ]]; then
        echo "  - No wireguard SSH keys found"
    fi
    
    print_command "Orphaned AWS resources (by tag, not in Terraform state):"
    local project_name="wireguard-setup"
    if command -v aws &> /dev/null; then
        # Check instances
        local orphan_instances
        orphan_instances=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=${project_name}-*" "Name=instance-state-name,Values=running,stopped,pending" \
            --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
            --output text 2>/dev/null || echo "")
        if [[ -n "$orphan_instances" ]]; then
            echo "  EC2 Instances:"
            echo "$orphan_instances" | while read -r line; do echo "    - $line"; done
        fi
        
        # Check NAT Gateways
        local orphan_nats
        orphan_nats=$(aws ec2 describe-nat-gateways \
            --filter "Name=tag:Name,Values=${project_name}-*" "Name=state,Values=available,pending" \
            --query 'NatGateways[*].NatGatewayId' --output text 2>/dev/null || echo "")
        if [[ -n "$orphan_nats" ]]; then
            echo "  NAT Gateways (💸 \$1.08/day each!):"
            echo "$orphan_nats" | while read -r line; do echo "    - $line"; done
        fi
        
        # Check Elastic IPs
        local orphan_eips
        orphan_eips=$(aws ec2 describe-addresses \
            --filters "Name=tag:Name,Values=${project_name}-*" \
            --query 'Addresses[*].PublicIp' --output text 2>/dev/null || echo "")
        if [[ -n "$orphan_eips" ]]; then
            echo "  Elastic IPs:"
            echo "$orphan_eips" | while read -r line; do echo "    - $line"; done
        fi
        
        # Check VPCs
        local orphan_vpcs
        orphan_vpcs=$(aws ec2 describe-vpcs \
            --filters "Name=tag:Name,Values=${project_name}-*" \
            --query 'Vpcs[*].VpcId' --output text 2>/dev/null || echo "")
        if [[ -n "$orphan_vpcs" ]]; then
            echo "  VPCs:"
            echo "$orphan_vpcs" | while read -r line; do echo "    - $line"; done
        fi
        
        # Check Security Groups
        local orphan_sgs
        orphan_sgs=$(aws ec2 describe-security-groups \
            --filters "Name=tag:Name,Values=${project_name}-*" \
            --query 'SecurityGroups[*].GroupId' --output text 2>/dev/null || echo "")
        if [[ -n "$orphan_sgs" ]]; then
            echo "  Security Groups:"
            echo "$orphan_sgs" | while read -r line; do echo "    - $line"; done
        fi
        
        # Check Key Pairs
        local orphan_keys
        orphan_keys=$(aws ec2 describe-key-pairs \
            --filters "Name=key-name,Values=${project_name}-*" \
            --query 'KeyPairs[*].KeyName' --output text 2>/dev/null || echo "")
        if [[ -n "$orphan_keys" ]]; then
            echo "  Key Pairs:"
            echo "$orphan_keys" | while read -r line; do echo "    - $line"; done
        fi
        
        if [[ -z "$orphan_instances" && -z "$orphan_nats" && -z "$orphan_eips" && -z "$orphan_vpcs" && -z "$orphan_sgs" && -z "$orphan_keys" ]]; then
            echo "  - No orphaned AWS resources found"
        fi
    else
        echo "  - AWS CLI not available, cannot check"
    fi
    
    echo
    print_success "=== DRY-RUN COMPLETED ==="
    print_command "No actual changes were made. This was a safe preview."
    print_command "To perform actual cleanup, run without --dry-run flag."
}

# Clean up project-specific SSH keys
cleanup_project_ssh_keys() {
    print_status "Cleaning up project-specific SSH keys..."
    
    local keys_found=false
    local keys_to_remove=()
    
    # 1) Current stable key path from terraform.tfvars (if present)
    if [[ -f "terraform/terraform.tfvars" ]]; then
        local tf_private_path
        tf_private_path=$(grep -E '^private_key_path\s*=' terraform/terraform.tfvars | sed 's/.*=\s*"\(.*\)".*/\1/' || true)
        if [[ -n "${tf_private_path:-}" ]]; then
            if [[ -f "$tf_private_path" ]]; then
                keys_to_remove+=("$tf_private_path")
                keys_found=true
            fi
            if [[ -f "${tf_private_path}.pub" ]]; then
                keys_to_remove+=("${tf_private_path}.pub")
                keys_found=true
            fi
        fi
    fi
    
    # 2) Find ALL wireguard keys in ~/.ssh using multiple patterns:
    #    - Stable key: wireguard-wireguard-setup (no timestamp)
    #    - Timestamped keys: wireguard-wireguard-setup-TIMESTAMP
    #    - Any other wireguard-* keys that might exist
    for key_file in ~/.ssh/wireguard-*; do
        if [[ -f "$key_file" ]]; then
            # Avoid duplicates (already added from tfvars)
            local already_added=false
            for existing in "${keys_to_remove[@]}"; do
                if [[ "$existing" == "$key_file" ]]; then
                    already_added=true
                    break
                fi
            done
            if [[ "$already_added" == "false" ]]; then
                keys_to_remove+=("$key_file")
                keys_found=true
            fi
        fi
    done
    
    if [ "$keys_found" = true ]; then
        print_status "Found project-specific SSH keys:"
        for key_file in "${keys_to_remove[@]}"; do
            print_status "  - $(basename "$key_file")"
        done
        
        if confirm_action "Remove these project-specific SSH keys?"; then
            for key_file in "${keys_to_remove[@]}"; do
                print_status "Removing: $(basename "$key_file")"
                rm -f "$key_file"
            done
            print_success "Project-specific SSH keys cleaned up"
        else
            print_warning "Skipping SSH key cleanup"
        fi
    else
        print_status "No project-specific SSH keys found"
    fi
}

# Clean up orphaned AWS key pairs not tracked by Terraform
cleanup_orphaned_aws_keypairs() {
    print_status "Checking for orphaned AWS key pairs..."
    
    # Get project name from tfvars or use default
    local project_name="wireguard-setup"
    if [[ -f "terraform/terraform.tfvars" ]]; then
        local tf_project
        tf_project=$(grep -E '^project_name\s*=' terraform/terraform.tfvars | sed 's/.*=\s*"\(.*\)".*/\1/' || true)
        if [[ -n "${tf_project:-}" ]]; then
            project_name="$tf_project"
        fi
    fi
    
    local expected_key_name="${project_name}-key"
    
    # Check if the key exists in AWS
    if ! command -v aws &> /dev/null; then
        print_warning "AWS CLI not available, skipping AWS key pair cleanup"
        return 0
    fi
    
    local aws_key_exists
    aws_key_exists=$(aws ec2 describe-key-pairs --key-names "$expected_key_name" 2>/dev/null || echo "")
    
    if [[ -z "$aws_key_exists" ]]; then
        print_status "No orphaned AWS key pair found"
        return 0
    fi
    
    # Check if it's tracked by Terraform
    local in_tf_state=false
    if [[ -f "terraform/terraform.tfstate" ]]; then
        cd terraform
        if terraform state list 2>/dev/null | grep -q "aws_key_pair.wireguard_key"; then
            in_tf_state=true
        fi
        cd ..
    fi
    
    if [[ "$in_tf_state" == "true" ]]; then
        print_status "AWS key pair '$expected_key_name' is tracked by Terraform (will be destroyed with infrastructure)"
        return 0
    fi
    
    # Key exists in AWS but not in Terraform state - it's orphaned
    print_warning "Found orphaned AWS key pair: $expected_key_name"
    print_warning "This key exists in AWS but is NOT tracked by Terraform state"
    
    if confirm_action "Delete orphaned AWS key pair '$expected_key_name'?"; then
        if aws ec2 delete-key-pair --key-name "$expected_key_name"; then
            print_success "Deleted orphaned AWS key pair: $expected_key_name"
        else
            print_error "Failed to delete AWS key pair: $expected_key_name"
        fi
    else
        print_warning "Skipping orphaned AWS key pair cleanup"
    fi
}

# Main execution
main() {
    local mode="quick"
    local check_orphans=false
    
    # Parse all arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --full)
                mode="full"
                shift
                ;;
            --ultra)
                mode="ultra"
                shift
                ;;
            --dry-run)
                mode="dry-run"
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --check-orphans)
                check_orphans=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo
                show_help
                exit 1
                ;;
        esac
    done
    
    # Run orphan check if requested
    if [[ "$check_orphans" == "true" ]]; then
        check_directory
        cd terraform
        print_header "Checking for orphaned AWS resources..."
        cleanup_orphaned_aws_resources
        cd ..
        return 0
    fi
    
    # Run selected mode
    case "$mode" in
        full)
            full_mode
            ;;
        ultra)
            ultra_mode
            ;;
        dry-run)
            dry_run_mode
            ;;
        quick)
            quick_mode
            ;;
    esac
}

# Run main function
main "$@"
