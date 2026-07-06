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

variable "subnet_ids" {
  description = "List of subnet IDs for the DB subnet group (must span at least 2 AZs)"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for the RDS instance (allows port 3306 from EKS nodes)"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class — db.t4g.micro qualifies for free tier (ARM/Graviton)"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum storage ceiling in GB for autoscaling (0 disables autoscaling; set equal to allocated_storage to cap at initial size)"
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment for high availability (doubles cost — disabled for learning)"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups (0 disables backups)"
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when deleting the instance (true for dev, false for prod)"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of the RDS instance"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to merge with default resource tags"
  type        = map(string)
  default     = {}
}
