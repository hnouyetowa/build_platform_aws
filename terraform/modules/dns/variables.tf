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

variable "domain_name" {
  description = "Root domain name for the Route 53 hosted zone (e.g. petclinic.example.com)"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS name to create the Route 53 alias A record (PETPLAT-31). Set after the ALB Ingress is deployed. Leave empty to skip A record creation."
  type        = string
  default     = ""
}

variable "alb_hosted_zone_id" {
  description = "AWS-managed hosted zone ID for ALBs in the deployment region. Default is eu-central-1."
  type        = string
  default     = "Z215JYRZR1TBD5"
}

variable "tags" {
  description = "Additional tags to merge with default resource tags"
  type        = map(string)
  default     = {}
}
