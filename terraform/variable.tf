variable "environment" {
  description = "Deployment environment for the NHS analytics platform"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be dev, test, or prod."
  }
}

variable "workspace_name" {
  description = "Name of the existing Microsoft Fabric workspace"
  type        = string
  default     = "NHS Fabric Dev"
}