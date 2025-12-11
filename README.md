# WireGuard AWS Remote Setup

Automated WireGuard VPN setup on AWS with bastion host and private instance architecture.

## 🏗️ Architecture

```
                             +------------------------+
                             |      Your Laptop       |
                             |   wg0: 10.0.3.3/24     |
                             +-----------+------------+
                                         |
                            WireGuard VPN (UDP 51820)
                               10.0.3.0/24 overlay
                                         |
        +------------------------------------------------------------------------+
        |                    AWS VPC 10.0.0.0/16                                 |
        |                                                                        |
        |  +------------------------------+     +------------------------------+ |
        |  | Public Subnet 10.0.1.0/24    |     | Private Subnet 10.0.2.0/24   | |
        |  |  +------------------------+  |     |  +------------------------+  | |
        |  |  | Bastion EC2 (WG server)|  |     |  | Private EC2 (WG client)|  | |
        |  |  | pub: elastic IP        |  |     |  | no public IP           |  | |
        |  |  | eth0: 10.0.1.x         |  |     |  | eth0: 10.0.2.x         |  | |
        |  |  | wg0:  10.0.3.1         |  |     |  | wg0:  10.0.3.2         |  | |
        |  |  +------------------------+  |     |  +------------------------+  | |
        |  +------------------------------+     +------------------------------+ |
        +------------------------------------------------------------------------+
```

- **VPC**: Custom VPC with public/private subnets
- **Bastion Host**: Public EC2 instance acting as WireGuard server
- **Private Instance**: Private EC2 instance accessible only via bastion or VPN
- **WireGuard Network**: 10.0.3.0/24 overlay connecting laptop, bastion, and private

## 🚀 Usage

### Complete Setup
```bash
./scripts/setup.sh
```

### WireGuard Client Setup
```bash
# Quick mode (recommended)
./scripts/wireguard_client.sh

# Auto mode (full automation)
./scripts/wireguard_client.sh --auto
```

### Cleanup
```bash
# Quick cleanup
./scripts/cleanup.sh

# Full cleanup (including local WireGuard)
./scripts/cleanup.sh --full

# Ultra cleanup (complete system cleanup)
./scripts/cleanup.sh --ultra
```

## 📋 Prerequisites

1. **AWS CLI configured**: `aws configure`
2. **Terraform installed**: [Download](https://terraform.io/downloads)
3. **Ansible installed**: `pip install ansible`
4. **WireGuard installed**: `sudo apt install wireguard` (for client setup)

## 🔧 What It Does

1. **Deploys AWS infrastructure** (VPC, EC2 instances, security groups)
2. **Configures WireGuard** on bastion and private instances
3. **Generates local client config** for VPN connection
4. **Provides cleanup scripts** for complete resource removal

## 🛡️ Security Features

- **Network Segmentation**: VPC with public/private subnets
- **Bastion Host**: Secure gateway to private resources
- **Security Groups**: Restrictive access controls
- **WireGuard Encryption**: Modern, secure VPN protocol
- **Key-based Authentication**: SSH key pairs for access
- **Dynamic IP Detection**: Automatic SSH access restriction to your public IP only
- **No Open SSH**: Bastion host SSH access is restricted to your detected public IP
- **Restricted WireGuard**: WireGuard port access limited to your IP only
- **SSH Hardening**: Enhanced SSH security with fail2ban and secure configurations
- **Retry Logic**: Automatic retry mechanisms for improved reliability

## 📚 Documentation

- **[DETAILED_GUIDE.md](DETAILED_GUIDE.md)**: Comprehensive setup and usage guide
- **[terraform/README.md](terraform/README.md)**: Infrastructure documentation
- **[ansible/README.md](ansible/README.md)**: Configuration management
