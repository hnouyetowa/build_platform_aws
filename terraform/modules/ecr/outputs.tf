output "repository_urls" {
  description = "Map of service_name → ECR repository URL"
  value       = { for name, repo in aws_ecr_repository.service : name => repo.repository_url }
}

output "repository_arns" {
  description = "Map of service_name → ECR repository ARN"
  value       = { for name, repo in aws_ecr_repository.service : name => repo.arn }
}

output "image_tag_mutability" {
  description = "Tag mutability setting applied to all repositories in this environment"
  value       = var.image_tag_mutability
}
