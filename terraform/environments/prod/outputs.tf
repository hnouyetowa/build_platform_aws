output "vpc_id" {
  description = "ID of the prod VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the prod public subnets"
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_sg_id" {
  description = "EKS cluster security group ID"
  value       = module.vpc.eks_cluster_sg_id
}

output "eks_node_sg_id" {
  description = "EKS node security group ID"
  value       = module.vpc.eks_node_sg_id
}

output "rds_sg_id" {
  description = "RDS security group ID"
  value       = module.vpc.rds_sg_id
}

output "alb_sg_id" {
  description = "ALB security group ID"
  value       = module.vpc.alb_sg_id
}

# ── EKS Outputs ───────────────────────────────────────────────────────────────

output "cluster_name" {
  description = "Name of the prod EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Prod EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for prod IRSA roles"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL (without https://) for prod IRSA trust policies"
  value       = module.eks.oidc_provider_url
}

output "node_group_name" {
  description = "Prod managed node group name"
  value       = module.eks.node_group_name
}

output "node_role_arn" {
  description = "Prod EKS worker node IAM role ARN"
  value       = module.eks.node_role_arn
}

output "ebs_csi_role_arn" {
  description = "Prod EBS CSI driver IRSA role ARN"
  value       = module.eks.ebs_csi_role_arn
}

output "kubeconfig_update_command" {
  description = "Command to configure kubectl for prod cluster access"
  value       = module.eks.kubeconfig_update_command
}

# ── DNS Outputs ───────────────────────────────────────────────────────────────

output "zone_id" {
  description = "Prod Route 53 hosted zone ID"
  value       = module.dns.zone_id
}

output "name_servers" {
  description = "Prod Route 53 NS records — delegate these at your registrar"
  value       = module.dns.name_servers
}

output "certificate_arn" {
  description = "Prod ACM wildcard certificate ARN — use in Ingress annotation"
  value       = module.dns.certificate_arn
}

output "app_url" {
  description = "Prod application HTTPS URL"
  value       = module.dns.app_url
}

output "lb_controller_role_arn" {
  description = "Prod ALB controller IRSA role ARN — annotate the ServiceAccount"
  value       = module.eks.lb_controller_role_arn
}

# ── RDS Outputs ───────────────────────────────────────────────────────────────

output "rds_endpoint" {
  description = "Prod RDS MySQL endpoint hostname"
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "Prod RDS port (3306)"
  value       = module.rds.port
}

output "rds_db_instance_id" {
  description = "Prod RDS instance identifier"
  value       = module.rds.db_instance_id
}

output "rds_secret_arn" {
  description = "Prod RDS credentials secret ARN (used by External Secrets Operator)"
  value       = module.rds.secret_arn
}

output "rds_connection_url" {
  description = "Prod JDBC connection URL for K8s ConfigMaps"
  value       = module.rds.connection_url
}

# ── ECR Outputs ───────────────────────────────────────────────────────────────

output "ecr_repository_urls" {
  description = "Map of service_name → ECR repository URL for prod"
  value       = module.ecr.repository_urls
}

output "ecr_repository_arns" {
  description = "Map of service_name → ECR repository ARN for prod"
  value       = module.ecr.repository_arns
}
