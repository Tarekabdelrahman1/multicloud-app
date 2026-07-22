variable "project_id" {
  description = "The Google Cloud project ID where resources will be created."
  type        = string
}

variable "region" {
  description = "The default Google Cloud region for regional resources."
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "The deployment environment name."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "Environment must be one of: dev, stage, or prod."
  }
}
variable "zone" {
  type = string
}

variable "artifact_registry_repository_id" {
  type = string
}
