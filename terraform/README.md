# WireGuard AWS Infrastructure (Terraform)

This configuration provisions a minimal, secure AWS network for experimenting with a WireGuard-based remote access pattern. It creates a dedicated VPC with a public subnet hosting a bastion (also your WireGuard endpoint) and a private subnet hosting an internal VM reachable only via SSH tunneling through the bastion. Security groups allow WireGuard UDP and narrowly scoped SSH (auto-detected to your public IP by default).

The setup uses the official VPC module (v6) for correctness and maintainability, Ubuntu 22.04 LTS AMIs discovered dynamically per-region, and sane defaults (no NAT gateway) to keep costs low. Region defaults to `eu-north-1`, and the bastion SSH ingress CIDR can be overridden via a variable or auto-detected locally using `curl`/`jq`.

## Requirements

- Terraform >= 1.0
- AWS account with credentials configured (e.g. `aws configure`) and permissions to manage VPC/EC2/SG/KeyPair
- Existing SSH keypair files on your local host
  - Public key path (e.g. `~/.ssh/id_rsa.pub`)
  - Private key path (e.g. `~/.ssh/id_rsa`)
- Local tools: `curl` and `jq` (used to auto-detect your public IP for bastion SSH allow-list)
- Internet egress from your workstation to reach AWS APIs and IP detection endpoints

## Usage

1. Copy variables and adjust:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```
   Update values (region defaults to `eu-north-1`). Optionally set `allowed_ssh_cidr` to bypass auto-detection.

2. Initialize and apply:
   ```bash
   terraform init -upgrade
   terraform plan
   terraform apply
   ```

3. Connect using outputs:
   ```bash
   # Bastion
   ssh -i ~/.ssh/id_rsa ubuntu@<bastion_public_ip>

   # Private via bastion
   ssh -i ~/.ssh/id_rsa -o ProxyCommand='ssh -i ~/.ssh/id_rsa -W %h:%p ubuntu@<bastion_public_ip>' ubuntu@<private_instance_ip>
   ```

## Cleanup

```bash
terraform destroy
```
