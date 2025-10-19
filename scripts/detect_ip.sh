#!/bin/bash
# Simple IP detection script that fails gracefully

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# Function to detect public IP
detect_public_ip() {
    local ip=""
    
    print_info "Detecting your public IP address..."
    
    # Try curl first
    if command -v curl >/dev/null 2>&1; then
        ip=$(curl -s --connect-timeout 5 --max-time 10 ifconfig.me 2>/dev/null || echo "")
        if [[ -n "$ip" && $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            print_success "Detected IP via curl: $ip"
            echo "$ip"
            return 0
        fi
    fi
    
    # Try dig
    if command -v dig >/dev/null 2>&1; then
        ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null || echo "")
        if [[ -n "$ip" && $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            print_success "Detected IP via dig: $ip"
            echo "$ip"
            return 0
        fi
    fi
    
    # Try wget
    if command -v wget >/dev/null 2>&1; then
        ip=$(wget -qO- --timeout=10 ifconfig.me 2>/dev/null || echo "")
        if [[ -n "$ip" && $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            print_success "Detected IP via wget: $ip"
            echo "$ip"
            return 0
        fi
    fi
    
    # All methods failed
    print_error "Could not detect your public IP address"
    print_error "Tried: curl, dig, wget - all failed"
    print_error ""
    print_error "To fix this:"
    print_error "1. Check your internet connection"
    print_error "2. Try running the setup again"
    print_error "3. Or manually set your IP in ansible/group_vars/all.yml:"
    print_error "   allowed_ssh_cidrs: \"YOUR_IP/32\""
    print_error "   allowed_wireguard_cidrs: \"YOUR_IP/32\""
    print_error ""
    print_error "Example:"
    print_error "   allowed_ssh_cidrs: \"203.0.113.10/32\""
    print_error "   allowed_wireguard_cidrs: \"203.0.113.10/32\""
    
    exit 1
}

# Main function
main() {
    detect_public_ip
}

# Run main function
main "$@"
