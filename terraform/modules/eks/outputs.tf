output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint URL for the EKS API server"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate for the EKS cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider (required for IRSA)"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL without https:// prefix (used in IRSA trust policies)"
  value       = local.oidc_provider_id
}

output "node_group_name" {
  description = "Name of the managed node group"
  value       = aws_eks_node_group.main.node_group_name
}

output "node_role_arn" {
  description = "ARN of the IAM role for EKS worker nodes"
  value       = aws_iam_role.node.arn
}

output "ebs_csi_role_arn" {
  description = "ARN of the IRSA role for the EBS CSI driver"
  value       = aws_iam_role.ebs_csi.arn
}

output "kubeconfig_update_command" {
  description = "Run this command locally to configure kubectl access to the cluster"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${data.aws_region.current.name}"
}

output "lb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller — annotate the ServiceAccount with this"
  value       = aws_iam_role.lb_controller.arn
}

output "vpc_id" {
  description = "VPC ID the cluster runs in — required for the ALB controller Helm values"
  value       = aws_eks_cluster.main.vpc_config[0].vpc_id
}
