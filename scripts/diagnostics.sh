#!/bin/bash

# Comprehensive Diagnostics Script
# Checks Oracle machine, WireGuard VPN, and kubeconfig status

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Get infrastructure info from Terraform state
get_infrastructure_info() {
    print_header "1. INFRASTRUCTURE STATUS (AWS Instances)"
    
    cd terraform
    
    if [ ! -f terraform.tfstate ]; then
        print_error "Terraform state file not found!"
        return 1
    fi
    
    BASTION_IP=$(terraform output -raw bastion_public_ip 2>/dev/null || echo "")
    PRIVATE_IP=$(terraform output -raw private_instance_ip 2>/dev/null || echo "")
    BASTION_PRIVATE_IP=$(terraform output -raw bastion_private_ip 2>/dev/null || echo "")
    
    if [ -z "$BASTION_IP" ]; then
        print_error "Could not get bastion IP from Terraform"
        cd ..
        return 1
    fi
    
    print_info "Bastion Public IP: $BASTION_IP"
    print_info "Bastion Private IP: $BASTION_PRIVATE_IP"
    print_info "Private Instance IP: $PRIVATE_IP"
    
    # Check AWS instance status
    print_info "Checking AWS instance status..."
    
    BASTION_INSTANCE_ID=$(terraform output -raw bastion_public_ip 2>/dev/null | xargs -I {} aws ec2 describe-instances --filters "Name=ip-address,Values={}" --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || echo "")
    
    if [ -n "$BASTION_INSTANCE_ID" ] && [ "$BASTION_INSTANCE_ID" != "None" ]; then
        BASTION_STATE=$(aws ec2 describe-instances --instance-ids "$BASTION_INSTANCE_ID" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "unknown")
        if [ "$BASTION_STATE" = "running" ]; then
            print_success "Bastion instance is running"
        else
            print_error "Bastion instance state: $BASTION_STATE"
        fi
    else
        # Try alternative method
        BASTION_STATE=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=wireguard-setup-bastion" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "unknown")
        if [ "$BASTION_STATE" = "running" ]; then
            print_success "Bastion instance is running"
        else
            print_warning "Could not verify bastion instance state (may need AWS CLI access)"
        fi
    fi
    
    cd ..
}

# Check SSH connectivity
check_ssh_connectivity() {
    print_header "2. SSH CONNECTIVITY"
    
    SSH_KEY="${HOME}/.ssh/wireguard-wireguard-setup"
    
    if [ ! -f "$SSH_KEY" ]; then
        print_error "SSH key not found at $SSH_KEY"
        return 1
    fi
    
    print_success "SSH key found: $SSH_KEY"
    
    # Test bastion SSH
    print_info "Testing SSH to bastion ($BASTION_IP)..."
    if timeout 10 ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o IdentitiesOnly=yes ubuntu@$BASTION_IP "echo 'SSH connection successful'" 2>/dev/null; then
        print_success "SSH to bastion works"
    else
        print_error "SSH to bastion failed"
    fi
    
    # Test private instance via bastion
    if [ -n "$PRIVATE_IP" ]; then
        print_info "Testing SSH to private instance ($PRIVATE_IP) via bastion..."
        if timeout 15 ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ProxyCommand="ssh -i \"$SSH_KEY\" -W %h:%p ubuntu@$BASTION_IP" ubuntu@$PRIVATE_IP "echo 'SSH connection successful'" 2>/dev/null; then
            print_success "SSH to private instance via bastion works"
        else
            print_error "SSH to private instance via bastion failed"
        fi
    fi
}

# Check WireGuard on bastion
check_wireguard_bastion() {
    print_header "3. WIREGUARD VPN STATUS (Bastion)"
    
    SSH_KEY="${HOME}/.ssh/wireguard-wireguard-setup"
    
    print_info "Checking WireGuard service on bastion..."
    
    # Check if WireGuard is installed
    if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o IdentitiesOnly=yes ubuntu@$BASTION_IP "command -v wg" 2>/dev/null; then
        print_success "WireGuard is installed on bastion"
    else
        print_error "WireGuard is NOT installed on bastion"
        return 1
    fi
    
    # Check WireGuard service status
    WG_STATUS=$(ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o IdentitiesOnly=yes ubuntu@$BASTION_IP "sudo systemctl is-active wg-quick@wg0 2>/dev/null || echo 'inactive'" 2>/dev/null || echo "unknown")
    
    if [ "$WG_STATUS" = "active" ]; then
        print_success "WireGuard service is active on bastion"
    else
        print_error "WireGuard service is $WG_STATUS on bastion"
    fi
    
    # Check WireGuard interface
    print_info "Checking WireGuard interface on bastion..."
    WG_INTERFACE=$(ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o IdentitiesOnly=yes ubuntu@$BASTION_IP "sudo wg show 2>/dev/null || echo 'no interface'" 2>/dev/null || echo "error")
    
    if [ "$WG_INTERFACE" != "no interface" ] && [ "$WG_INTERFACE" != "error" ] && [ -n "$WG_INTERFACE" ]; then
        print_success "WireGuard interface is up on bastion"
        echo "$WG_INTERFACE" | head -10
    else
        print_error "WireGuard interface is NOT up on bastion"
    fi
    
    # Get server public key
    SERVER_PUBLIC_KEY=$(ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o IdentitiesOnly=yes ubuntu@$BASTION_IP "sudo cat /etc/wireguard/wg0_public_key 2>/dev/null || echo ''" 2>/dev/null || echo "")
    
    if [ -n "$SERVER_PUBLIC_KEY" ]; then
        print_success "Server public key found: ${SERVER_PUBLIC_KEY:0:20}..."
    else
        print_error "Server public key not found"
    fi
}

# Check WireGuard locally
check_wireguard_local() {
    print_header "4. WIREGUARD VPN STATUS (Local Machine)"
    
    # Check if WireGuard is installed locally
    if command -v wg &> /dev/null; then
        print_success "WireGuard is installed locally"
    else
        print_error "WireGuard is NOT installed locally"
        return 1
    fi
    
    # Check if WireGuard interface is up
    if ip link show wg0 &>/dev/null || ifconfig wg0 &>/dev/null 2>&1; then
        print_success "WireGuard interface (wg0) exists"
        
        # Check if it's up
        WG_STATUS=$(sudo wg show 2>/dev/null || echo "")
        if [ -n "$WG_STATUS" ]; then
            print_success "WireGuard interface is active"
            echo "$WG_STATUS" | head -10
        else
            print_warning "WireGuard interface exists but may not be active"
        fi
    else
        print_error "WireGuard interface (wg0) does NOT exist"
    fi
    
    # Check for local config
    if [ -f "/etc/wireguard/wg0.conf" ]; then
        print_success "WireGuard config found at /etc/wireguard/wg0.conf"
    elif [ -f "local_wg0.conf" ]; then
        print_warning "Local config found at local_wg0.conf (not installed)"
    else
        print_error "No WireGuard config found"
    fi
}

# Test VPN connectivity
test_vpn_connectivity() {
    print_header "5. VPN CONNECTIVITY TESTS"
    
    # Test bastion via VPN
    print_info "Testing connectivity to bastion via VPN (10.0.3.1)..."
    if ping -c 2 -W 2 10.0.3.1 &>/dev/null; then
        print_success "Bastion (10.0.3.1) is reachable via VPN"
    else
        print_error "Bastion (10.0.3.1) is NOT reachable via VPN"
    fi
    
    # Test private instance via VPN
    if [ -n "$PRIVATE_IP" ]; then
        print_info "Testing connectivity to private instance via VPN (10.0.3.2)..."
        if ping -c 2 -W 2 10.0.3.2 &>/dev/null; then
            print_success "Private instance (10.0.3.2) is reachable via VPN"
        else
            print_error "Private instance (10.0.3.2) is NOT reachable via VPN"
        fi
    fi
    
    # Test private instance direct IP via VPN
    if [ -n "$PRIVATE_IP" ]; then
        print_info "Testing connectivity to private instance direct IP via VPN ($PRIVATE_IP)..."
        if ping -c 2 -W 2 "$PRIVATE_IP" &>/dev/null; then
            print_success "Private instance ($PRIVATE_IP) is reachable via VPN"
        else
            print_warning "Private instance ($PRIVATE_IP) is NOT reachable via VPN (may be expected)"
        fi
    fi
}

# Note: Kubernetes checks removed - not relevant to WireGuard VPN project

# Summary
print_summary() {
    print_header "6. SUMMARY"
    
    echo "Infrastructure:"
    echo "  - Bastion IP: $BASTION_IP"
    echo "  - Private IP: $PRIVATE_IP"
    echo ""
    echo "Next steps if issues found:"
    echo "  1. If WireGuard not running on bastion:"
    echo "     ssh -i ~/.ssh/wireguard-wireguard-setup -o StrictHostKeyChecking=no ubuntu@$BASTION_IP"
    echo "     sudo systemctl start wg-quick@wg0"
    echo ""
    echo "  2. If WireGuard not configured locally:"
    echo "     ./scripts/wireguard_client.sh --auto"
    echo ""
    echo "  3. If VPN not working:"
    echo "     Check your WireGuard interface: ip link show type wireguard"
    echo "     Start it: sudo wg-quick up <interface>"
    echo "     Check status: sudo wg show"
}

# Main execution
main() {
    print_header "WIREGUARD VPN DIAGNOSTICS"
    
    # Get infrastructure info first
    if ! get_infrastructure_info; then
        print_error "Failed to get infrastructure information"
        exit 1
    fi
    
    check_ssh_connectivity
    check_wireguard_bastion
    check_wireguard_local
    test_vpn_connectivity
    print_summary
}

# Run main function
main "$@"



