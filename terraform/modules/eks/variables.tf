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

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "subnet_ids" {
  description = "List of public subnet IDs for the EKS cluster and node group"
  type        = list(string)
}

variable "cluster_sg_id" {
  description = "Security group ID for the EKS cluster control plane"
  type        = string
}

variable "node_sg_id" {
  description = "Security group ID for the EKS worker nodes"
  type        = string
}

variable "node_instance_types" {
  description = "Instance types for the managed node group (ARM/Graviton)"
  type        = list(string)
  default     = ["t4g.small"]
}

variable "node_ami_type" {
  description = "AMI type for the managed node group"
  type        = string
  default     = "AL2_ARM_64"
}

variable "node_min_size" {
  description = "Minimum number of nodes in the managed node group"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes in the managed node group"
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired number of nodes in the managed node group"
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "EBS root volume size in GB for each worker node"
  type        = number
  default     = 20
}

variable "admin_iam_principal_arn" {
  description = "IAM principal ARN granted cluster-admin access via EKS access entry. Defaults to the Terraform caller identity when empty."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to merge with default resource tags"
  type        = map(string)
  default     = {}
}
