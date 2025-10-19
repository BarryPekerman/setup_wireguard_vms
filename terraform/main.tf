# AWS Provider configuration
provider "aws" {
  region = var.aws_region
}

# Optionally auto-detect the caller's public IP for SSH if not provided
data "external" "caller_ip" {
  program = [
    "bash",
    "-lc",
    "IP=$(curl -4 -s --connect-timeout 5 https://api.ipify.org || curl -4 -s --connect-timeout 5 https://ipv4.icanhazip.com || dig +short myip.opendns.com @resolver1.opendns.com || echo 0.0.0.0); jq -n --arg ip \"$IP\" '{ip: $ip}'"
  ]
}

locals {
  detected_ip_cidr   = format("%s/32", trimspace(data.external.caller_ip.result.ip))
  ssh_cidr_effective = length(trimspace(var.allowed_ssh_cidr)) > 0 ? var.allowed_ssh_cidr : local.detected_ip_cidr
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# Prefer SSM Parameter Store for region-correct Ubuntu AMI IDs
# AMI lookup for Ubuntu 22.04 (Jammy) in current region (Canonical owner)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC Module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = [data.aws_availability_zones.available.names[0]]
  public_subnets  = [var.public_subnet_cidr]
  private_subnets = [var.private_subnet_cidr]


  enable_nat_gateway = true
  single_nat_gateway = true
  enable_vpn_gateway = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    Name = "${var.project_name}-public-subnet"
    Type = "public"
  }

  private_subnet_tags = {
    Name = "${var.project_name}-private-subnet"
    Type = "private"
  }

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = "development"
    Project     = "wireguard-setup"
  }
}


# Security Group for Bastion Host
resource "aws_security_group" "bastion_sg" {
  name_prefix = "${var.project_name}-bastion-"
  vpc_id      = module.vpc.vpc_id

  # SSH access from anywhere (restrict this in production)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.ssh_cidr_effective]
  }

  # WireGuard port - restricted to your IP only
  ingress {
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = [local.ssh_cidr_effective]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-bastion-sg"
  }
}

# Security Group for Private Instance
resource "aws_security_group" "private_sg" {
  name_prefix = "${var.project_name}-private-"
  vpc_id      = module.vpc.vpc_id

  # SSH access from bastion host
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # WireGuard port - restricted to bastion host only
  ingress {
    from_port       = 51820
    to_port         = 51820
    protocol        = "udp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # Allow all traffic from VPC
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-private-sg"
  }
}

# Key Pair
resource "aws_key_pair" "wireguard_key" {
  key_name   = "${var.project_name}-key"
  public_key = file(var.public_key_path)

  tags = {
    Name = "${var.project_name}-key"
  }
}

# No SSM IAM roles needed for SSH-only approach

# Bastion Host (Public Subnet)
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.wireguard_key.key_name
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true
  source_dest_check           = false

  tags = {
    Name = "${var.project_name}-bastion"
  }
}

# Route private subnet default route through bastion to enable egress without NAT GW
# Remove custom route via instance; NAT GW will be managed by the VPC module

# Private Instance
resource "aws_instance" "private" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.wireguard_key.key_name
  subnet_id              = module.vpc.private_subnets[0]
  vpc_security_group_ids = [aws_security_group.private_sg.id]

  tags = {
    Name = "${var.project_name}-private"
  }
}

# Outputs moved to outputs.tf
