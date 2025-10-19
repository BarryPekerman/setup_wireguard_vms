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
    echo "Modes:"
    echo "  Quick Mode (default):"
    echo "    - Generates local_wg0.conf"
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
    echo "  $0                  # Quick setup"
    echo "  $0 --auto           # Full automation"
}

# Check if WireGuard is installed
check_wireguard() {
    if ! command -v wg &> /dev/null; then
        print_error "WireGuard is not installed. Please install it first:"
        print_command "sudo apt update && sudo apt install wireguard"
        exit 1
    fi
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
    
    SERVER_PUBLIC_KEY=$(ssh -i terraform/keys/wireguard_key -o StrictHostKeyChecking=no -o IdentitiesOnly=yes ubuntu@$BASTION_PUBLIC_IP "sudo cat /etc/wireguard/wg0_public_key")
    
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
    
    cat > local_wg0.conf << EOF
[Interface]
PrivateKey = $LOCAL_PRIVATE_KEY
Address = 10.0.3.3/24

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $BASTION_PUBLIC_IP:51820
AllowedIPs = 10.0.3.0/24, 10.0.2.0/24
PersistentKeepalive = 25
EOF

    print_success "Created local_wg0.conf"
}

# Add client to server
add_client_to_server() {
    print_header "Adding local client to server configuration..."
    
    ssh -i terraform/keys/wireguard_key -o StrictHostKeyChecking=no -o IdentitiesOnly=yes ubuntu@$BASTION_PUBLIC_IP "sudo wg set wg0 peer $LOCAL_PUBLIC_KEY allowed-ips 10.0.3.3/32"
    
    print_success "Added local client to server"
}

# Install WireGuard config (auto mode only)
install_wireguard_config() {
    print_header "Installing WireGuard configuration..."
    
    sudo cp local_wg0.conf /etc/wireguard/wg0.conf
    sudo chmod 600 /etc/wireguard/wg0.conf
    
    print_success "Installed WireGuard configuration to /etc/wireguard/wg0.conf"
}

# Start WireGuard (auto mode only)
start_wireguard() {
    print_header "Starting WireGuard interface..."
    
    sudo wg-quick up wg0
    
    print_success "WireGuard interface started"
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
    echo
    print_command "=== WIREGUARD SETUP COMPLETE ==="
    echo
    print_command "1. Install and start WireGuard:"
    echo "sudo cp local_wg0.conf /etc/wireguard/wg0.conf"
    echo "sudo wg-quick up wg0"
    echo
    print_command "2. SSH to bastion:"
    echo "ssh -i terraform/keys/wireguard_key -o IdentitiesOnly=yes ubuntu@10.0.3.1"
    echo
    print_command "3. SSH to private instance:"
    echo "ssh -i terraform/keys/wireguard_key -o IdentitiesOnly=yes ubuntu@10.0.3.2"
    echo
    print_command "4. Check WireGuard status:"
    echo "sudo wg show"
    echo
    print_command "5. Disconnect VPN:"
    echo "sudo wg-quick down wg0"
    echo
    print_command "6. Reconnect VPN:"
    echo "sudo wg-quick up wg0"
}

# Display auto mode completion
show_auto_completion() {
    echo
    print_success "=== WIREGUARD VPN IS NOW ACTIVE ==="
    echo
    print_command "SSH to bastion:"
    echo "ssh -i terraform/keys/wireguard_key -o IdentitiesOnly=yes ubuntu@10.0.3.1"
    echo
    print_command "SSH to private instance:"
    echo "ssh -i terraform/keys/wireguard_key -o IdentitiesOnly=yes ubuntu@10.0.3.2"
    echo
    print_command "Check WireGuard status:"
    echo "sudo wg show"
    echo
    print_command "Disconnect VPN:"
    echo "sudo wg-quick down wg0"
}

# Quick mode (default)
quick_mode() {
    print_status "Running in Quick Mode - config generation only"
    echo
    
    check_wireguard
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

