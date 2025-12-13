#!/bin/bash

# Unified WireGuard Client Setup Script
# Usage: 
#   ./scripts/wireguard_client.sh           # Quick config generation (default)
#   ./scripts/wireguard_client.sh --auto    # Full auto-setup
#   ./scripts/wireguard_client.sh --help    # Show help

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
    echo "WireGuard Client Setup Script"
    echo
    echo "Usage:"
    echo "  $0                 # Quick config generation (default)"
    echo "  $0 --auto          # Full auto-setup"
    echo "  $0 --help          # Show this help"
    echo
    echo "Environment Variables:"
    echo "  WG_INTERFACE       # Interface name (default: wg0)"
    echo "                     # Use this if wg0 is already in use by another VPN"
    echo
    echo "Modes:"
    echo "  Quick Mode (default):"
    echo "    - Checks for existing WireGuard interfaces"
    echo "    - Generates local_\${WG_INTERFACE}.conf"
    echo "    - Adds client to server"
    echo "    - Shows commands to run manually"
    echo
    echo "  Auto Mode (--auto):"
    echo "    - Does everything in Quick Mode"
    echo "    - Installs config to /etc/wireguard/"
    echo "    - Starts WireGuard interface"
    echo "    - Tests connectivity"
    echo
    echo "Examples:"
    echo "  $0                       # Quick setup (uses wg0)"
    echo "  $0 --auto                # Full automation (uses wg0)"
    echo "  WG_INTERFACE=wg1 $0      # Use wg1 instead of wg0"
    echo "  WG_INTERFACE=wg1 $0 --auto  # Auto mode with wg1"
}

# Configuration
WG_INTERFACE="${WG_INTERFACE:-wg0}"

# Check if WireGuard is installed
check_wireguard() {
    if ! command -v wg &> /dev/null; then
        print_error "WireGuard is not installed. Please install it first:"
        print_command "sudo apt update && sudo apt install wireguard"
        exit 1
    fi
}

# Check for existing WireGuard interfaces and find available interface name
check_interface_conflicts() {
    print_header "Checking for existing WireGuard interfaces..."
    
    # Get list of existing WireGuard interfaces
    local existing_interfaces
    existing_interfaces=$(ip link show type wireguard 2>/dev/null | grep -oP '^\d+:\s+\K[^:@]+' || true)
    
    if [[ -z "$existing_interfaces" ]]; then
        print_status "No existing WireGuard interfaces found"
        return 0
    fi
    
    print_warning "Found existing WireGuard interfaces:"
    echo "$existing_interfaces" | while read -r iface; do
        echo "  - $iface"
    done
    
    # Check if our desired interface already exists
    if echo "$existing_interfaces" | grep -qx "$WG_INTERFACE"; then
        print_warning "Interface '$WG_INTERFACE' already exists!"
        
        # Check if it's ours by looking at the config
        if [[ -f "/etc/wireguard/${WG_INTERFACE}.conf" ]]; then
            local existing_endpoint
            existing_endpoint=$(grep -oP 'Endpoint\s*=\s*\K[^:]+' "/etc/wireguard/${WG_INTERFACE}.conf" 2>/dev/null || echo "unknown")
            print_warning "Existing config points to endpoint: $existing_endpoint"
        fi
        
        # Find next available interface
        local next_num=1
        while echo "$existing_interfaces" | grep -qx "wg${next_num}"; do
            next_num=$((next_num + 1))
        done
        local suggested_interface="wg${next_num}"
        
        echo
        print_error "Interface '$WG_INTERFACE' is already in use!"
        print_status "Options:"
        echo "  1. Use a different interface: WG_INTERFACE=$suggested_interface $0 $*"
        echo "  2. Stop the existing interface: sudo wg-quick down $WG_INTERFACE"
        echo "  3. Check what's using it: sudo wg show $WG_INTERFACE"
        echo
        
        read -p "Do you want to use '$suggested_interface' instead? [y/N]: " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            WG_INTERFACE="$suggested_interface"
            print_status "Using interface: $WG_INTERFACE"
        else
            print_error "Cannot proceed with interface '$WG_INTERFACE' already in use"
            exit 1
        fi
    fi
}

# Determine which SSH key to use for connecting to bastion. Prefer the
# project-specific key path from terraform.tfvars, with a sane fallback to
# the stable default path used by setup.sh.
get_ssh_key_path() {
    local key_path=""
    if [[ -f terraform/terraform.tfvars ]]; then
        key_path=$(grep -E '^private_key_path\s*=' terraform/terraform.tfvars | sed 's/.*=\s*"\(.*\)".*/\1/' || true)
    fi
    if [[ -z "$key_path" ]]; then
        key_path="$HOME/.ssh/wireguard-wireguard-setup"
    fi
    echo "$key_path"
}

# Get infrastructure details from Terraform
get_infrastructure_info() {
    print_header "Getting infrastructure information from Terraform..."
    
    cd terraform
    
    BASTION_PUBLIC_IP=$(terraform output -raw bastion_public_ip)
    BASTION_PRIVATE_IP=$(terraform output -raw private_instance_ip)
    
    if [[ -z "$BASTION_PUBLIC_IP" || -z "$BASTION_PRIVATE_IP" ]]; then
        print_error "Could not get infrastructure information. Make sure Terraform has been applied."
        exit 1
    fi
    
    print_status "Bastion Public IP: $BASTION_PUBLIC_IP"
    print_status "Private Instance IP: $BASTION_PRIVATE_IP"
    
    cd ..
}

# Get server public key from bastion
get_server_public_key() {
    print_header "Getting server public key from bastion..."
    
    local ssh_key
    ssh_key=$(get_ssh_key_path)
    
    SERVER_PUBLIC_KEY=$(ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o IdentitiesOnly=yes ubuntu@$BASTION_PUBLIC_IP "sudo cat /etc/wireguard/wg0_public_key")
    
    if [[ -z "$SERVER_PUBLIC_KEY" ]]; then
        print_error "Could not get server public key from bastion"
        exit 1
    fi
    
    print_status "Server Public Key: $SERVER_PUBLIC_KEY"
}

# Generate local client keys
generate_client_keys() {
    print_header "Generating local client keys..."
    
    # Generate private key
    LOCAL_PRIVATE_KEY=$(wg genkey)
    
    # Generate public key
    LOCAL_PUBLIC_KEY=$(echo "$LOCAL_PRIVATE_KEY" | wg pubkey)
    
    print_status "Local Private Key: $LOCAL_PRIVATE_KEY"
    print_status "Local Public Key: $LOCAL_PUBLIC_KEY"
}

# Create local WireGuard config
create_wireguard_config() {
    print_header "Creating local WireGuard configuration..."
    
    local config_file="local_${WG_INTERFACE}.conf"
    
    cat > "$config_file" << EOF
[Interface]
PrivateKey = $LOCAL_PRIVATE_KEY
Address = 10.0.3.3/24

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $BASTION_PUBLIC_IP:51820
AllowedIPs = 10.0.3.0/24, 10.0.2.0/24
PersistentKeepalive = 25
EOF

    print_success "Created $config_file"
    
    # Save state so cleanup knows which interface we created
    echo "$WG_INTERFACE" > .wireguard_interface
    echo "$BASTION_PUBLIC_IP" > .wireguard_endpoint
    print_status "Saved interface state for cleanup"
}

# Add client to server
add_client_to_server() {
    print_header "Adding local client to server configuration..."
    
    local ssh_key
    ssh_key=$(get_ssh_key_path)
    
    ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o IdentitiesOnly=yes ubuntu@$BASTION_PUBLIC_IP "sudo wg set wg0 peer $LOCAL_PUBLIC_KEY allowed-ips 10.0.3.3/32"
    
    print_success "Added local client to server"
}

# Install WireGuard config (auto mode only)
install_wireguard_config() {
    print_header "Installing WireGuard configuration..."
    
    local config_file="local_${WG_INTERFACE}.conf"
    
    sudo cp "$config_file" "/etc/wireguard/${WG_INTERFACE}.conf"
    sudo chmod 600 "/etc/wireguard/${WG_INTERFACE}.conf"
    
    print_success "Installed WireGuard configuration to /etc/wireguard/${WG_INTERFACE}.conf"
}

# Start WireGuard (auto mode only)
start_wireguard() {
    print_header "Starting WireGuard interface..."
    
    sudo wg-quick up "$WG_INTERFACE"
    
    print_success "WireGuard interface '$WG_INTERFACE' started"
}

# Test connectivity (auto mode only)
test_connectivity() {
    print_header "Testing connectivity..."
    
    # Test bastion
    if ping -c 1 10.0.3.1 &> /dev/null; then
        print_success "✓ Bastion (10.0.3.1) is reachable"
    else
        print_error "✗ Bastion (10.0.3.1) is not reachable"
    fi
    
    # Test private instance
    if ping -c 1 10.0.3.2 &> /dev/null; then
        print_success "✓ Private instance (10.0.3.2) is reachable"
    else
        print_error "✗ Private instance (10.0.3.2) is not reachable"
    fi
}

# Display connection commands (quick mode)
show_connection_commands() {
    local ssh_key
    ssh_key=$(get_ssh_key_path)
    local config_file="local_${WG_INTERFACE}.conf"
    
    echo
    print_command "=== WIREGUARD SETUP COMPLETE ==="
    echo
    print_command "1. Install and start WireGuard:"
    echo "sudo cp $config_file /etc/wireguard/${WG_INTERFACE}.conf"
    echo "sudo wg-quick up $WG_INTERFACE"
    echo
    print_command "2. Test connectivity (verify VPN is working):"
    echo "ping -c 3 10.0.3.1    # Bastion via VPN"
    echo "ping -c 3 10.0.3.2    # Private instance via VPN"
    echo
    print_command "3. SSH to bastion (via VPN):"
    echo "ssh -i \"$ssh_key\" ubuntu@10.0.3.1"
    echo
    print_command "4. SSH to private instance (via VPN):"
    echo "ssh -i \"$ssh_key\" ubuntu@10.0.3.2"
    echo
    print_command "5. Check WireGuard status:"
    echo "sudo wg show"
    echo
    print_command "6. Disconnect VPN:"
    echo "sudo wg-quick down $WG_INTERFACE"
    echo
    print_command "7. Reconnect VPN:"
    echo "sudo wg-quick up $WG_INTERFACE"
    echo
    print_warning "⚠️  'REMOTE HOST IDENTIFICATION HAS CHANGED' error?"
    echo "   This happens if old SSH host keys exist from a previous deployment."
    echo "   Fix: ssh-keygen -R 10.0.3.1 && ssh-keygen -R 10.0.3.2"
    echo "   Or run: ./scripts/cleanup.sh (removes old entries automatically)"
    echo ""
    echo "   ⚠️  INSECURE WORKAROUND (use only if cleanup didn't help):"
    echo "   ssh -i \"$ssh_key\" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@10.0.3.1"
}

# Display auto mode completion
show_auto_completion() {
    local ssh_key
    ssh_key=$(get_ssh_key_path)
    
    echo
    print_success "=== WIREGUARD VPN IS NOW ACTIVE (interface: $WG_INTERFACE) ==="
    echo
    print_command "SSH to bastion (via VPN):"
    echo "ssh -i \"$ssh_key\" ubuntu@10.0.3.1"
    echo
    print_command "SSH to private instance (via VPN):"
    echo "ssh -i \"$ssh_key\" ubuntu@10.0.3.2"
    echo
    print_command "Check WireGuard status:"
    echo "sudo wg show"
    echo
    print_command "Disconnect VPN:"
    echo "sudo wg-quick down $WG_INTERFACE"
    echo
    print_warning "⚠️  'REMOTE HOST IDENTIFICATION HAS CHANGED' error?"
    echo "   Fix: ssh-keygen -R 10.0.3.1 && ssh-keygen -R 10.0.3.2"
}

# Quick mode (default)
quick_mode() {
    print_status "Running in Quick Mode - config generation only"
    echo
    
    check_wireguard
    check_interface_conflicts
    get_infrastructure_info
    get_server_public_key
    generate_client_keys
    create_wireguard_config
    add_client_to_server
    show_connection_commands
    
    print_success "Quick setup completed! Follow the commands above to connect."
}

# Auto mode
auto_mode() {
    print_status "Running in Auto Mode - full automation"
    echo
    
    check_wireguard
    check_interface_conflicts
    get_infrastructure_info
    get_server_public_key
    generate_client_keys
    create_wireguard_config
    add_client_to_server
    install_wireguard_config
    start_wireguard
    test_connectivity
    show_auto_completion
    
    print_success "Auto setup completed! WireGuard VPN is now active."
}

# Main execution
main() {
    # Parse arguments
    case "${1:-}" in
        --auto)
            auto_mode
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

