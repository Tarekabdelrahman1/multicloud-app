variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "network_id" {
  type = string
}

variable "subnet_id" {
  type = string
}
variable "service_account_email" {
  description = "Service account used by GKE nodes."
  type        = string
}
variable "zone" {
  type = string
}
