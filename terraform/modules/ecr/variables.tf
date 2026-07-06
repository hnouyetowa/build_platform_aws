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

variable "service_names" {
  description = "List of service names — one ECR repository is created per entry"
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "Tag mutability for all ECR repositories: MUTABLE for dev, IMMUTABLE for prod"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be 'MUTABLE' or 'IMMUTABLE'."
  }
}

variable "tags" {
  description = "Additional tags to merge with default resource tags"
  type        = map(string)
  default     = {}
}
