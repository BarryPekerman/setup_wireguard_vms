# WireGuard AWS Showcase Project 🚀

**A learning project demonstrating modern DevOps practices:** Infrastructure as Code (Terraform), Configuration Management (Ansible), and WireGuard VPN deployment on AWS.

> ⚠️ **Note:** This is a **showcase/learning project** demonstrating DevOps skills and tools. Not intended for production use without additional hardening and security measures.

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
- **Private Instance**: Private EC2 instance accessible via SSH tunnel or WireGuard VPN
- **WireGuard Network**: 10.0.3.0/24 overlay connecting laptop, bastion, and private
- **Access Methods**: 
  - SSH tunneling (traditional bastion pattern) - for setup and management
  - WireGuard VPN (modern VPN pattern) - for ongoing secure access

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

## 🎯 What This Project Demonstrates

### Technical Skills Showcased
- ✅ **Infrastructure as Code**: Terraform for AWS resource provisioning
- ✅ **Configuration Management**: Ansible for automated system configuration
- ✅ **Cloud Architecture**: VPC design with public/private subnets
- ✅ **VPN Technology**: WireGuard implementation and configuration
- ✅ **Automation**: End-to-end deployment scripts with error handling
- ✅ **DevOps Practices**: Retry logic, cleanup procedures, diagnostics

### Technologies Used
- **Terraform** (~6.0) - Infrastructure provisioning
- **Ansible** - Configuration management
- **AWS** - EC2, VPC, Security Groups
- **WireGuard** - Modern VPN protocol
- **Bash** - Automation scripting

### Architecture Concepts Demonstrated
- **Network Segmentation**: VPC with public/private subnets
- **Bastion Host Pattern**: Secure gateway to private resources
- **Security Groups**: Network-level access controls
- **VPN Overlay Network**: WireGuard mesh connecting multiple endpoints
- **Dynamic IP Detection**: Automated security group configuration

## 📚 Documentation

- **[DETAILED_GUIDE.md](DETAILED_GUIDE.md)**: Comprehensive setup and usage guide
- **[terraform/README.md](terraform/README.md)**: Infrastructure documentation
- **[ansible/README.md](ansible/README.md)**: Configuration management
- **[SHOWCASE.md](SHOWCASE.md)**: LinkedIn showcase highlights and talking points

## 🎓 Learning Objectives

This project demonstrates understanding of:
1. **Infrastructure as Code** principles and Terraform best practices
2. **Configuration Management** using Ansible playbooks
3. **AWS Networking** (VPC, subnets, security groups, routing)
4. **VPN Technologies** (WireGuard configuration and deployment)
5. **Automation** (end-to-end deployment scripts)
6. **DevOps Workflows** (setup, testing, cleanup procedures)

## ⚠️ Important Notes

- **Purpose**: This is a **showcase/learning project** for demonstrating DevOps skills
- **Not Production-Ready**: Additional security hardening, monitoring, and operational procedures would be needed for production use
- **Cost**: Uses minimal AWS resources (t3.nano instances) for cost-effective learning
- **Cleanup**: Always run cleanup scripts when done to avoid AWS charges
