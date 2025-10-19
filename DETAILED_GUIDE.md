# WireGuard AWS Setup - Detailed Guide

Comprehensive documentation for the WireGuard AWS Remote Setup project.

## 📁 Project Structure

```
setup-wireguard-remote/
├── terraform/                 # Infrastructure as Code
│   ├── main.tf               # Main Terraform configuration
│   ├── variables.tf          # Variable definitions
│   ├── outputs.tf            # Output definitions
│   ├── versions.tf           # Provider version constraints
│   ├── keys/                 # SSH key pairs
│   └── README.md             # Terraform documentation
├── ansible/                   # Configuration management
│   ├── playbooks/            # Ansible playbooks
│   ├── templates/            # Configuration templates
│   ├── inventory/            # Ansible inventory
│   ├── group_vars/           # Ansible variables
│   └── README.md             # Ansible documentation
├── scripts/                   # Automation scripts
│   ├── setup.sh              # Complete setup script
│   ├── wireguard_client.sh   # WireGuard client setup (3 modes)
│   └── cleanup.sh             # Cleanup script (3 modes)
├── DETAILED_GUIDE.md         # This comprehensive guide
└── README.md                  # Main documentation
```

## 🔧 Scripts Overview

### Setup Script (`scripts/setup.sh`)
- **Purpose**: Complete end-to-end setup
- **Features**: Infrastructure deployment, Ansible configuration, testing
- **Usage**: `./scripts/setup.sh`

### WireGuard Client Script (`scripts/wireguard_client.sh`)
- **Quick Mode**: Generates config and shows commands
- **Auto Mode**: Full automation including system changes
- **Usage**: `./scripts/wireguard_client.sh [--auto|--help]`

### Cleanup Script (`scripts/cleanup.sh`)
- **Quick Mode**: Infrastructure + local files cleanup
- **Full Mode**: Including local WireGuard cleanup
- **Ultra Mode**: Complete system cleanup including backups
- **Usage**: `./scripts/cleanup.sh [--full|--ultra|--help]`

## 🛡️ Security Features

- **Network Segmentation**: VPC with public/private subnets
- **Bastion Host**: Secure gateway to private resources
- **Security Groups**: Restrictive access controls
- **WireGuard Encryption**: Modern, secure VPN protocol
- **Key-based Authentication**: SSH key pairs for access
- **Fail2ban**: Protection against brute force attacks
- **Dynamic IP Detection**: Automatic SSH access restriction to your public IP only
- **No Open SSH**: Bastion host SSH access is restricted to your detected public IP
- **Restricted WireGuard**: WireGuard port access limited to your IP only
- **SSH Hardening**: Enhanced SSH security with fail2ban and secure configurations
- **Retry Logic**: Automatic retry mechanisms for improved reliability

## 📊 Three-Tier Automation System

### Setup Tiers
| Tier  | Description                    | Use Case                |
|-------|--------------------------------|-------------------------|
| Quick | Config generation + commands   | Development, learning   |
| Auto  | Full automation                | Production, convenience |

### Cleanup Tiers
| Tier  | Description                    | Use Case                |
|-------|--------------------------------|-------------------------|
| Quick | Infrastructure + local files  | Development, testing     |
| Full  | Including local WireGuard      | Production cleanup      |
| Ultra | Complete system cleanup        | Complete reset          |

## 🔄 Workflow Examples

### Development Workflow
```bash
# Setup
./scripts/setup.sh
./scripts/wireguard_client.sh

# Test and develop
# ... work with VPN ...

# Cleanup
./scripts/cleanup.sh
```

### Production Workflow
```bash
# Setup
./scripts/setup.sh
./scripts/wireguard_client.sh --auto

# Production use
# ... work with VPN ...

# Cleanup
./scripts/cleanup.sh --full
```

### Complete Reset Workflow
```bash
# Setup
./scripts/setup.sh
./scripts/wireguard_client.sh --auto

# Production use
# ... work with VPN ...

# Complete cleanup
./scripts/cleanup.sh --ultra
```

## 🧪 Testing

### Set Up Local WireGuard Client

The project includes a unified WireGuard client setup script with two modes:

#### Quick Mode (Recommended)
```bash
# Generate config and show commands to run manually
./scripts/wireguard_client.sh
```

#### Auto Mode (Full Automation)
```bash
# Automatically install, start, and test WireGuard
./scripts/wireguard_client.sh --auto
```

#### Show All Options
```bash
./scripts/wireguard_client.sh --help
```

### Test WireGuard Connection

```bash
# From local machine
ping 10.0.3.1  # Bastion WireGuard IP
ping 10.0.3.2  # Private instance WireGuard IP

# Check WireGuard status
sudo wg show
```

### Test Private Instance Access

```bash
# Via bastion host
ssh -i ~/.ssh/id_rsa ubuntu@<bastion_ip>
ssh ubuntu@<private_ip>

# Direct via WireGuard (if configured)
ssh ubuntu@10.0.3.2
```

## 🧹 Cleanup

The project includes a comprehensive cleanup script with three modes:

### Quick Cleanup (Default)
```bash
./scripts/cleanup.sh
```
- ✅ Destroys AWS infrastructure
- ✅ Removes local config files
- ✅ Shows commands to clean local WireGuard
- ✅ **Safe with confirmations**

### Full Cleanup (Complete Automation)
```bash
./scripts/cleanup.sh --full
```
- ✅ Does everything in Quick Mode
- ✅ Stops and removes local WireGuard interface
- ✅ Removes WireGuard config from system
- ✅ Cleans up SSH config entries
- ⚠️ **More automated but requires confirmations**

### Ultra Cleanup (Complete System Cleanup)
```bash
./scripts/cleanup.sh --ultra
```
- ✅ Does everything in Full Mode
- ✅ Removes backup files
- ✅ Removes remaining WireGuard configs
- ✅ Complete system cleanup
- ⚠️ **Most automated but requires confirmations**

### Show Cleanup Options
```bash
./scripts/cleanup.sh --help
```

### Safety Features
- **🛡️ Confirmation Prompts**: Asks before destructive actions
- **💾 Backup Creation**: Creates backups before cleanup (except ultra mode)
- **🔍 Dry-run Mode**: Shows what will be destroyed
- **📋 Step-by-step**: Clear progress indicators
- **🔄 Recovery Options**: Backups available until ultra mode
- **🧠 Smart Detection**: Automatically skips empty infrastructure

### Cleanup Mode Comparison

| Feature             | Quick        | Full         | Ultra        |
|---------------------|--------------|--------------|--------------|
| AWS Infrastructure  | ✅           | ✅           | ✅           |
| Local Files         | ✅           | ✅           | ✅           |
| WireGuard Interface | 📋 Commands  | ✅           | ✅           |
| WireGuard Config    | 📋 Commands  | ✅           | ✅           |
| SSH Config          | ❌           | ✅           | ✅           |
| Backup Files        | 💾 Created   | 💾 Created   | ❌ Removed   |
| System Configs      | ❌           | ❌           | ✅           |
| Recovery Possible   | ✅           | ✅           | ❌           |

## 🔒 Security Considerations

### Critical Security Issues to Address:

1. **Restrict SSH Access**: Limit to your office/home IPs
2. **Enable Logging**: VPC Flow Logs and CloudTrail
3. **Key Management**: Use AWS Secrets Manager
4. **Monitoring**: Set up GuardDuty and Security Hub

### Security Checklist

- [ ] Restrict SSH access to specific IPs
- [ ] Enable VPC Flow Logs
- [ ] Set up CloudTrail
- [ ] Implement key rotation
- [ ] Add network ACLs
- [ ] Enable GuardDuty
- [ ] Set up Security Hub
- [ ] Configure Config rules
- [ ] Add WAF if needed
- [ ] Implement least privilege IAM
- [ ] Enable encryption at rest
- [ ] Set up monitoring and alerting
- [ ] Document security procedures
- [ ] Regular security assessments

## 🔄 Alternative Connection Methods

### 1. NAT Gateway + Elastic IP
- Private instance gets outbound internet access
- Can establish WireGuard connection from private to public
- **Pros**: No bastion host needed
- **Cons**: More complex routing, higher cost

### 2. AWS Client VPN
- AWS managed VPN solution
- **Pros**: Fully managed, highly available
- **Cons**: More expensive, AWS-specific

### 3. Application Load Balancer
- For specific applications only
- **Pros**: Highly available
- **Cons**: Complex setup, limited use cases

## 🎯 Key Features

### Automation
- ✅ **Infrastructure as Code**: Terraform for AWS resources
- ✅ **Configuration Management**: Ansible for system setup
- ✅ **Three-Tier Scripts**: Quick, Full, Ultra modes
- ✅ **Safety First**: Confirmation prompts and backups

### Flexibility
- ✅ **User Control**: Choose automation level
- ✅ **Transparency**: See exactly what's happening
- ✅ **Recovery**: Backups available until ultra mode
- ✅ **Learning**: Understand the process

### Safety
- ✅ **Confirmation Prompts**: Every destructive action
- ✅ **Backup Creation**: Automatic backups before cleanup
- ✅ **Error Handling**: Graceful failure handling
- ✅ **Validation**: Prerequisites and directory checks

## 📚 Additional Documentation

- **[terraform/README.md](terraform/README.md)**: Infrastructure setup
- **[ansible/README.md](ansible/README.md)**: Configuration management

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For issues and questions:
1. Check the documentation
2. Review the security recommendations
3. Open an issue on GitHub
