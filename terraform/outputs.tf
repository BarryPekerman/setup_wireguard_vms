# Infrastructure Outputs
output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_private_ip" {
  description = "Private IP of the bastion host"
  value       = aws_instance.bastion.private_ip
}

output "private_instance_ip" {
  description = "Private IP of the private instance"
  value       = aws_instance.private.private_ip
}


output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

# Connection Commands
output "bastion_ssh_command" {
  description = "SSH command to connect to bastion host"
  value       = "ssh -i ${var.private_key_path} ubuntu@${aws_instance.bastion.public_ip}"
}

output "private_ssh_command" {
  description = "SSH command to connect to private instance via bastion"
  value       = "ssh -i ${var.private_key_path} -o ProxyCommand='ssh -i ${var.private_key_path} -W %h:%p ubuntu@${aws_instance.bastion.public_ip}' ubuntu@${aws_instance.private.private_ip}"
}

# Network Information
output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = module.vpc.public_subnets[0]
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = module.vpc.private_subnets[0]
}

output "bastion_security_group_id" {
  description = "ID of the bastion security group"
  value       = aws_security_group.bastion_sg.id
}

output "private_security_group_id" {
  description = "ID of the private instance security group"
  value       = aws_security_group.private_sg.id
}

# VPC Module Outputs
output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = module.vpc.igw_id
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = module.vpc.public_route_table_ids[0]
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = module.vpc.private_route_table_ids[0]
}
