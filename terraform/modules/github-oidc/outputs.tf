output "role_arn" {
  description = "IAM role ARN for GitHub Actions — set as AWS_ROLE_ARN secret in the application repo"
  value       = aws_iam_role.github_actions.arn
}

output "role_name" {
  description = "IAM role name for GitHub Actions"
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN"
  value       = local.oidc_provider_arn
}

output "oidc_subject" {
  description = "OIDC subject claim that the trust policy accepts — shows exactly which repo+branch can assume the role"
  value       = local.oidc_subject
}

output "github_secrets_to_configure" {
  description = "GitHub Secrets to add to the application repo for the CI workflow to work"
  value = {
    AWS_ROLE_ARN   = aws_iam_role.github_actions.arn
    AWS_REGION     = data.aws_region.current.name
    AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id
  }
}
