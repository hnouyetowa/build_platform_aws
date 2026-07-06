variable "project" {
  description = "Project name used in resource naming and tagging"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be 'dev' or 'prod'."
  }
}

variable "cluster_name" {
  description = "EKS cluster name — used in EventBridge rules and Karpenter discovery tags"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider — from module.eks.oidc_provider_arn (NOT hardcoded)"
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL without https:// — from module.eks.oidc_provider_url (NOT hardcoded)"
  type        = string
}

variable "node_role_name" {
  description = "Name of the EKS worker node IAM role — used for the Karpenter node instance profile"
  type        = string
}

variable "node_role_arn" {
  description = "ARN of the EKS worker node IAM role — used to restrict PassRole to this role only"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "tags" {
  description = "Additional tags to merge with default resource tags"
  type        = map(string)
  default     = {}
}
