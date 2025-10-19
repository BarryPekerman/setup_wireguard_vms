# SSH Tunneling WireGuard AWS Setup

This directory contains a complete **SSH tunneling** solution for deploying WireGuard VPN infrastructure on AWS using pure SSH connections through a bastion host.

## 🎯 What This Does

- **Creates AWS Infrastructure**: VPC, subnets, security groups, instances
- **Configures SSH Tunneling**: Bastion host access to private instances
- **Configures WireGuard**: Automated VPN setup between instances
- **Sets up Security**: UFW firewall, fail2ban, SSH key authentication
- **Tests Connectivity**: SSH tunneling and WireGuard validation
- **Provides Cleanup**: Easy infrastructure removal

## 🚀 Quick Start

### **One-Command Setup:**
```bash
./scripts/setup.sh
```

### **Custom Configuration:**
```bash
# Custom region and project
AWS_REGION=eu-west-1 PROJECT_NAME=my-vpn ./scripts/setup.sh

# Restrict SSH access to your IP
ALLOWED_SSH_CIDRS=203.0.113.0/24 ./scripts/setup.sh
```

## 📁 Directory Structure

```
ansible/
├── playbooks/                 # Main playbooks
│   ├── site.yml              # Complete setup
│   ├── infrastructure.yml    # AWS infrastructure
│   ├── wireguard.yml         # WireGuard configuration
│   └── cleanup.yml           # Infrastructure cleanup
├── templates/                 # Configuration templates
│   ├── server.conf.j2        # WireGuard server config
│   ├── client.conf.j2        # WireGuard client config
│   ├── fail2ban.conf.j2      # Fail2ban configuration
│   └── infrastructure_inventory.j2
├── inventory/                # Dynamic inventory
│   ├── localhost.ini         # Local execution
│   └── infrastructure.ini    # Generated infrastructure
├── group_vars/               # Global variables
│   └── all.yml              # Default configuration
├── scripts/                  # Automation scripts
│   └── setup.sh             # Main setup script
├── ansible.cfg              # Ansible configuration
├── requirements.yml         # Collection requirements
└── README.md               # This file
```

## 🔧 Manual Execution

### **Step 1: Install Dependencies**
```bash
ansible-galaxy collection install -r requirements.yml
```

### **Step 2: Deploy Infrastructure**
```bash
ansible-playbook playbooks/infrastructure.yml \
  -e "aws_region=us-west-2" \
  -e "project_name=wireguard-setup"
```

### **Step 3: Configure WireGuard**
```bash
ansible-playbook playbooks/wireguard.yml \
  -i inventory/infrastructure.ini
```

## 🛡️ Security Features

- **Network Security**: VPC with public/private subnets
- **SSH Tunneling**: Encrypted connections through bastion host
- **Access Control**: SSH key-based authentication
- **Firewall**: UFW configuration
- **Intrusion Detection**: Fail2ban protection
- **Connection Multiplexing**: Efficient SSH connection reuse

## 🔄 Operations

### **Check Status:**
```bash
# Infrastructure status
ansible-playbook playbooks/infrastructure.yml --check

# WireGuard status
ansible wireguard -i inventory/infrastructure.ini -m shell -a "wg show"
```

### **Cleanup:**
```bash
# Remove all infrastructure
ansible-playbook playbooks/cleanup.yml

# Or use the script
./scripts/setup.sh cleanup
```

## 🧪 Testing

### **Automated Tests:**
```bash
# Run connectivity tests
./scripts/setup.sh test
```

### **Manual Verification:**
```bash
# SSH to bastion
ssh -i ~/.ssh/id_rsa ubuntu@<bastion_ip>

# SSH to private instance via bastion (SSH tunneling)
ssh -i ~/.ssh/id_rsa -o ProxyCommand='ssh -i ~/.ssh/id_rsa -W %h:%p ubuntu@<bastion_ip>' ubuntu@<private_ip>

# Test WireGuard connectivity
ping 10.0.3.1  # From your local machine
ping 10.0.3.2  # From bastion to private
```

## 🔧 Configuration

### **Environment Variables:**
```bash
export AWS_REGION=us-west-2
export PROJECT_NAME=wireguard-setup
export ALLOWED_SSH_CIDRS=203.0.113.0/24
export ALLOWED_WIREGUARD_CIDRS=203.0.113.0/24
```

### **Group Variables:**
Edit `group_vars/all.yml`:
```yaml
aws_region: us-west-2
project_name: wireguard-setup
allowed_ssh_cidrs: "203.0.113.0/24"  # Your office IP
allowed_wireguard_cidrs: "203.0.113.0/24"  # Your office IP
```

## 🚨 Troubleshooting

### **Common Issues:**

1. **AWS Credentials:**
   ```bash
   aws sts get-caller-identity
   ```

2. **SSH Key Issues:**
   ```bash
   ssh-add ~/.ssh/id_rsa
   ```

3. **Ansible Connection:**
   ```bash
   ansible all -i inventory/infrastructure.ini -m ping
   ```

4. **WireGuard Status:**
   ```bash
   ansible wireguard -i inventory/infrastructure.ini -m shell -a "wg show"
   ```

### **Debug Mode:**
```bash
ansible-playbook playbooks/site.yml -vvv
```

## 📊 Cost Optimization

### **Instance Types:**
- **t3.nano**: $0.0052/hour (default)
- **t3.micro**: $0.0104/hour
- **t3.small**: $0.0208/hour

### **Estimated Monthly Cost:**
- **t3.nano**: ~$3.74/month
- **t3.micro**: ~$7.49/month

## 🎯 Best Practices

1. **Use Variables**: Configure via environment variables
2. **Test First**: Run with `--check` flag
3. **Version Control**: Commit all configurations
4. **Monitor**: Set up CloudWatch alarms
5. **Backup**: Regular configuration backups
6. **Security**: Rotate keys regularly
7. **Documentation**: Keep runbooks updated

## 🆘 Support

For issues and questions:
1. Check the troubleshooting section
2. Review Ansible logs with `-vvv`
3. Test individual playbooks
4. Open an issue on GitHub