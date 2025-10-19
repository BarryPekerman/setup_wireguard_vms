#!/bin/bash

# Test IP detection methods with error handling
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# IP detection methods
ip_methods=(
    "curl -s --connect-timeout 5 --max-time 10 ifconfig.me"
    "curl -s --connect-timeout 5 --max-time 10 ipinfo.io/ip"
    "dig +short myip.opendns.com @resolver1.opendns.com"
    "wget -qO- --timeout=10 ifconfig.me"
    "curl -s --connect-timeout 5 --max-time 10 icanhazip.com"
)

print_header "Testing IP Detection Methods"

detected_ip=""
method_used=""

for method in "${ip_methods[@]}"; do
    print_status "Trying: $method"
    
    if result=$(eval "$method" 2>/dev/null); then
        if [[ "$result" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            detected_ip="$result"
            method_used="$method"
            print_status "✅ Success! Detected IP: $detected_ip"
            break
        else
            print_warning "Invalid IP format: $result"
        fi
    else
        print_warning "Method failed: $method"
    fi
done

if [[ -z "$detected_ip" ]]; then
    print_error "❌ All IP detection methods failed!"
    print_warning "Using fallback: 0.0.0.0/32 (NOT SECURE!)"
    detected_ip="0.0.0.0"
    method_used="fallback"
fi

print_header "Results"
echo "Detected IP: $detected_ip"
echo "Method used: $method_used"
echo "CIDR: ${detected_ip}/32"

if [[ "$detected_ip" == "0.0.0.0" ]]; then
    print_warning "⚠️  WARNING: Using fallback IP (0.0.0.0/32)"
    print_warning "This will allow SSH access from ANY IP address!"
    print_warning "Please manually set your IP in group_vars/all.yml"
else
    print_status "✅ IP detection successful!"
    print_status "SSH access will be restricted to: ${detected_ip}/32"
fi


