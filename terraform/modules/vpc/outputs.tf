output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "eks_cluster_sg_id" {
  description = "ID of the EKS cluster (control plane) security group"
  value       = aws_security_group.eks_cluster.id
}

output "eks_node_sg_id" {
  description = "ID of the EKS worker node security group"
  value       = aws_security_group.eks_node.id
}

output "rds_sg_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

output "alb_sg_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}
