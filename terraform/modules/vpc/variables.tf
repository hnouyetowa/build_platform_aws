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

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of availability zones for subnet placement"
  type        = list(string)
}

variable "tags" {
  description = "Additional tags to merge with default resource tags"
  type        = map(string)
  default     = {}
}
