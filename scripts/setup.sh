#!/bin/bash

# WireGuard AWS Setup Script
# This script automates the entire setup process

set -euo pipefail

# Optional env file support
set -a
[ -f ./.env ] && . ./.env || true
[ -f ./scripts/setup.env ] && . ./scripts/setup.env || true
set +a

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Detect local public IP
detect_local_ip() {
    print_status "Detecting your public IP address..."
    
    # Try multiple methods to get public IP
    LOCAL_IP=""
    
    # Method 1: curl to ipify.org
    if command -v curl &> /dev/null; then
        LOCAL_IP=$(curl -4 -s --connect-timeout 5 https://api.ipify.org 2>/dev/null || echo "")
    fi
    
    # Method 2: curl to icanhazip.com
    if [ -z "$LOCAL_IP" ] && command -v curl &> /dev/null; then
        LOCAL_IP=$(curl -4 -s --connect-timeout 5 https://ipv4.icanhazip.com 2>/dev/null || echo "")
    fi
    
    # Method 3: dig to OpenDNS
    if [ -z "$LOCAL_IP" ] && command -v dig &> /dev/null; then
        LOCAL_IP=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null || echo "")
    fi
    
    # Method 4: curl to httpbin.org
    if [ -z "$LOCAL_IP" ] && command -v curl &> /dev/null; then
        LOCAL_IP=$(curl -4 -s --connect-timeout 5 https://httpbin.org/ip 2>/dev/null | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1 || echo "")
    fi
    
    if [ -z "$LOCAL_IP" ]; then
        print_error "Could not detect your public IP address. Please set allowed_ssh_cidr manually in terraform/terraform.tfvars"
        exit 1
    fi
    
    print_status "Detected public IP: $LOCAL_IP"
    LOCAL_IP_CIDR="${LOCAL_IP}/32"
    print_status "SSH access will be restricted to: $LOCAL_IP_CIDR"
}

# Update terraform.tfvars with detected IP
update_terraform_config() {
    print_status "Updating Terraform configuration with your IP..."
    
    cd terraform
    
    # Check if terraform.tfvars exists
    if [ ! -f terraform.tfvars ]; then
        print_warning "terraform.tfvars not found. Creating from example..."
        cp terraform.tfvars.example terraform.tfvars
    fi
    
    # Update the allowed_ssh_cidr with detected IP
    if grep -q "allowed_ssh_cidr" terraform.tfvars; then
        # Update existing line
        sed -i "s|allowed_ssh_cidr = .*|allowed_ssh_cidr = \"$LOCAL_IP_CIDR\"|" terraform.tfvars
    else
        # Add new line
        echo "" >> terraform.tfvars
        echo "# Auto-detected IP for SSH access" >> terraform.tfvars
        echo "allowed_ssh_cidr = \"$LOCAL_IP_CIDR\"" >> terraform.tfvars
    fi
    
    print_status "Updated terraform.tfvars with your IP: $LOCAL_IP_CIDR"
    cd ..
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check if ansible is installed
    if ! command -v ansible &> /dev/null; then
        print_error "Ansible is not installed. Please install it first."
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
    
    print_status "All prerequisites met!"
}

# Deploy infrastructure with retry logic
deploy_infrastructure() {
    print_status "Deploying AWS infrastructure..."
    
    cd terraform
    
    # Initialize terraform with retry
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        print_status "Initializing Terraform (attempt $((retry_count + 1))/$max_retries)..."
        if terraform init -upgrade; then
            print_success "Terraform initialized successfully"
            break
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                print_warning "Terraform init failed, retrying in 30 seconds..."
                sleep 30
            else
                print_error "Terraform init failed after $max_retries attempts"
                cd ..
                return 1
            fi
        fi
    done
    
    # Plan with retry
    retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        print_status "Planning Terraform deployment (attempt $((retry_count + 1))/$max_retries)..."
        if terraform plan -out=tfplan; then
            print_success "Terraform plan successful"
            break
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                print_warning "Terraform plan failed, retrying in 30 seconds..."
                sleep 30
            else
                print_error "Terraform plan failed after $max_retries attempts"
                cd ..
                return 1
            fi
        fi
    done
    
    # Apply with retry
    retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        print_status "Applying Terraform deployment (attempt $((retry_count + 1))/$max_retries)..."
        if terraform apply -auto-approve tfplan; then
            print_success "Infrastructure deployed successfully"
            break
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                print_warning "Terraform apply failed, retrying in 60 seconds..."
                sleep 60
            else
                print_error "Infrastructure deployment failed after $max_retries attempts"
                print_error "Check AWS console for any resource conflicts or permission issues"
                cd ..
                return 1
            fi
        fi
    done
    
    cd ..
}

# Get infrastructure outputs
get_outputs() {
    print_status "Getting infrastructure outputs..."
    
    cd terraform
    BASTION_IP=$(terraform output -raw bastion_public_ip)
    PRIVATE_IP=$(terraform output -raw private_instance_ip)
    print_status "Bastion IP: $BASTION_IP"
    print_status "Private IP: $PRIVATE_IP"
    cd ..
}

# Update Ansible inventory
update_inventory() {
    print_status "Updating Ansible inventory..."

    bash ./ansible/scripts/generate_inventory_from_tf.sh

    print_status "Inventory generated at ansible/inventory/infrastructure.ini"
}

# Run Ansible playbook with retry logic
run_ansible() {
    print_status "Running Ansible playbook..."
    
    cd ansible
    
    # Install requirements with retry
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        print_status "Installing Ansible requirements (attempt $((retry_count + 1))/$max_retries)..."
        if ansible-galaxy collection install -r requirements.yml; then
            print_success "Ansible requirements installed successfully"
            break
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                print_warning "Ansible requirements installation failed, retrying in 30 seconds..."
                sleep 30
            else
                print_error "Failed to install Ansible requirements after $max_retries attempts"
                cd ..
                return 1
            fi
        fi
    done
    
    # Run playbook with retry
    retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        print_status "Running Ansible playbook (attempt $((retry_count + 1))/$max_retries)..."
        if ansible-playbook playbooks/wireguard.yml -i inventory/infrastructure.ini --timeout=300; then
            print_success "Ansible playbook completed successfully"
            break
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                print_warning "Ansible playbook failed, retrying in 60 seconds..."
                sleep 60
            else
                print_error "Ansible playbook failed after $max_retries attempts"
                print_error "Check SSH connectivity and instance status"
                cd ..
                return 1
            fi
        fi
    done
    
    cd ..
}

# Test connection
test_connection() {
    print_status "Testing WireGuard connection..."
    
    # Test bastion connectivity
    if ping -c 3 $BASTION_IP &> /dev/null; then
        print_status "Bastion host is reachable"
    else
        print_error "Cannot reach bastion host"
        return 1
    fi
    
    # Test private instance via bastion
    if ssh -i ~/.ssh/id_rsa -o ConnectTimeout=10 -o ProxyCommand="ssh -i ~/.ssh/id_rsa -W %h:%p ubuntu@$BASTION_IP" ubuntu@$PRIVATE_IP "echo 'Private instance reachable'" &> /dev/null; then
        print_status "Private instance is reachable via bastion"
    else
        print_warning "Cannot reach private instance via bastion"
    fi
}

# Cleanup function for failed deployments
cleanup_on_failure() {
    print_error "Setup failed! Cleaning up resources..."
    
    if [ -d "terraform" ] && [ -f "terraform/terraform.tfstate" ]; then
        print_warning "Destroying partially created infrastructure..."
        cd terraform
        terraform destroy -auto-approve || print_warning "Terraform destroy failed, manual cleanup may be required"
        cd ..
    fi
    
    print_error "Setup failed. Check the logs above for details."
    print_status "You can try running the setup again or use './scripts/cleanup.sh' to clean up any remaining resources."
    exit 1
}

# Main execution with enhanced error handling
main() {
    print_status "Starting WireGuard AWS Setup..."
    
    # Set up error handling
    trap cleanup_on_failure ERR
    
    # Execute setup steps with error checking
    if ! check_prerequisites; then
        print_error "Prerequisites check failed"
        exit 1
    fi
    
    if ! detect_local_ip; then
        print_error "IP detection failed"
        exit 1
    fi
    
    if ! update_terraform_config; then
        print_error "Terraform configuration update failed"
        exit 1
    fi
    
    if ! deploy_infrastructure; then
        print_error "Infrastructure deployment failed"
        cleanup_on_failure
    fi
    
    if ! get_outputs; then
        print_error "Failed to get infrastructure outputs"
        cleanup_on_failure
    fi
    
    if ! update_inventory; then
        print_error "Inventory update failed"
        cleanup_on_failure
    fi
    
    if ! run_ansible; then
        print_error "Ansible configuration failed"
        cleanup_on_failure
    fi
    
    if ! test_connection; then
        print_warning "Connection test failed, but setup may still be functional"
    fi
    
    # Clear error trap on success
    trap - ERR
    
    print_success "Setup completed successfully!"
    print_status "You can now connect to the private instance via:"
    print_status "ssh -i ~/.ssh/id_rsa -o ProxyCommand='ssh -i ~/.ssh/id_rsa -W %h:%p ubuntu@$BASTION_IP' ubuntu@$PRIVATE_IP"
    print_status ""
    print_status "To set up WireGuard VPN for direct access:"
    print_status "./scripts/wireguard_client.sh           # Quick config generation (recommended)"
    print_status "./scripts/wireguard_client.sh --auto    # Full auto-setup"
    print_status "./scripts/wireguard_client.sh --help    # Show all options"
    print_status ""
    print_status "To clean up everything when done:"
    print_status "./scripts/cleanup.sh                   # Quick cleanup (infrastructure + local files)"
    print_status "./scripts/cleanup.sh --full            # Full cleanup (including local WireGuard)"
    print_status "./scripts/cleanup.sh --ultra           # Ultra cleanup (complete system cleanup)"
    print_status "./scripts/cleanup.sh --help            # Show all cleanup options"
}

# Run main function
main "$@"

