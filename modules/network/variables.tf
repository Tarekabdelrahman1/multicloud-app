variable "project_id" {
  description = "Google Cloud project ID."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string
}

variable "network_name" {
  description = "Name of the VPC."
  type        = string
}
variable "region" {
  description = "Region where the subnet will be created."
  type        = string
}

variable "subnet_name" {
  description = "Name of the subnet."
  type        = string
}

variable "subnet_ip_cidr_range" {
  description = "Primary CIDR range of the subnet."
  type        = string
}
