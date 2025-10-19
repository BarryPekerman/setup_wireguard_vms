variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "wireguard-setup"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.nano"
}

variable "public_key_path" {
  description = "Path to the public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "private_key_path" {
  description = "Path to the private key file"
  type        = string
  default     = "~/.ssh/id_rsa"
}

# Optional: CIDR to allow SSH to the bastion. If empty, we will auto-detect
# the caller's public IP using a local shell command (external data source)
variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into the bastion (e.g. 203.0.113.10/32). Leave empty to auto-detect."
  type        = string
  default     = ""
}
