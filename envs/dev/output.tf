output "configuration_summary" {
  description = "Summary of the current Terraform environment."

  value = {
    project_id  = var.project_id
    region      = var.region
    environment = var.environment
  }
}
