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

variable "github_org" {
  description = "GitHub username or organization that owns the application repo. Derive dynamically from 'git remote get-url origin'."
  type        = string
}

variable "app_repo_name" {
  description = "GitHub repository name for the Spring Petclinic application fork (the repo whose CI pushes images to ECR)"
  type        = string
  default     = "spring-petclinic-microservices"
}

variable "branch" {
  description = "Branch the OIDC trust policy is restricted to (prevents tokens from PRs or other branches)"
  type        = string
  default     = "main"
}

variable "create_oidc_provider" {
  description = "Set to false if the GitHub Actions OIDC provider already exists in this AWS account (only one can exist per account)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to merge with default resource tags"
  type        = map(string)
  default     = {}
}
