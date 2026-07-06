variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be 'dev' or 'prod'."
  }
}

variable "domain_name" {
  description = "Root domain name for Route 53 hosted zone and ACM certificate (e.g. dev.petclinic.example.com)"
  type        = string
}

variable "project" {
  description = "Project name used in resource naming and tagging"
  type        = string
  default     = "petclinic"
}
