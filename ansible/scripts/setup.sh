#!/bin/bash

# Ansible-Only WireGuard AWS Setup Script
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

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if ansible is installed
    if ! command -v ansible &> /dev/null; then
        print_error "Ansible is not installed. Please install it first:"
        echo "pip install ansible"
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if SSH key exists
    if [ ! -f ~/.ssh/id_rsa ]; then
        print_error "SSH private key not found at ~/.ssh/id_rsa"
        exit 1
    fi
    
    # Check if boto3 is installed
    if ! python3 -c "import boto3" &> /dev/null; then
        print_warning "boto3 not found. Installing..."
        pip install boto3 botocore
    fi
    
    print_status "All prerequisites met!"
}

# Install Ansible collections
install_collections() {
    print_header "Installing Ansible Collections"
    
    ansible-galaxy collection install -r requirements.yml
    print_status "Collections installed successfully!"
}

# Run the complete setup
run_setup() {
    print_header "Running Complete WireGuard Setup"
    
    # Run the main site playbook
    ansible-playbook playbooks/site.yml \
        -e "aws_region=${AWS_REGION:-eu-north-1}" \
        -e "project_name=${PROJECT_NAME:-wireguard-setup}" \
        -e "allowed_ssh_cidrs=${ALLOWED_SSH_CIDRS:-0.0.0.0/0}" \
        -e "allowed_wireguard_cidrs=${ALLOWED_WIREGUARD_CIDRS:-0.0.0.0/0}" \
        -v
    
    print_status "Setup completed successfully!"
}

# Test connectivity
test_connectivity() {
    print_header "Testing Connectivity"
    
    if [ -f "inventory/infrastructure.ini" ]; then
        print_status "Testing WireGuard connection..."
        
        # Test bastion connectivity
        bastion_ip=$(grep "bastion ansible_host" inventory/infrastructure.ini | cut -d' ' -f2 | cut -d'=' -f2)
        if ping -c 3 $bastion_ip &> /dev/null; then
            print_status "✅ Bastion host is reachable"
        else
            print_warning "⚠️  Cannot reach bastion host"
        fi
        
        print_status "Connection test completed!"
    else
        print_warning "Infrastructure inventory not found. Skipping connectivity test."
    fi
}

# Display usage information
show_usage() {
    print_header "Usage Information"
    
    echo "Environment Variables:"
    echo "  AWS_REGION              - AWS region (default: eu-north-1)"
    echo "  PROJECT_NAME            - Project name (default: wireguard-setup)"
    echo "  ALLOWED_SSH_CIDRS       - SSH access CIDRs (default: 0.0.0.0/0)"
    echo "  ALLOWED_WIREGUARD_CIDRS - WireGuard access CIDRs (default: 0.0.0.0/0)"
    echo ""
    echo "Examples:"
    echo "  # Basic setup"
    echo "  ./scripts/setup.sh"
    echo ""
    echo "  # Custom region and project name"
    echo "  AWS_REGION=eu-west-1 PROJECT_NAME=my-vpn ./scripts/setup.sh"
    echo ""
    echo "  # Restrict SSH access to your IP"
    echo "  ALLOWED_SSH_CIDRS=203.0.113.0/24 ./scripts/setup.sh"
    echo ""
    echo "  # Cleanup"
    echo "  ansible-playbook playbooks/cleanup.yml"
}

# Main execution
main() {
    case "${1:-setup}" in
        "setup")
            check_prerequisites
            install_collections
            run_setup
            test_connectivity
            ;;
        "cleanup")
            print_header "Cleaning Up Infrastructure"
            ansible-playbook playbooks/cleanup.yml
            ;;
        "test")
            test_connectivity
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        *)
            print_error "Unknown command: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"


