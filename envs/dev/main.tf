provider "google" {
  project = var.project_id
  region  = var.region
}

module "network" {
  source = "../../modules/network"

  project_id           = var.project_id
  environment          = var.environment
  region               = var.region
  network_name         = "${var.environment}-vpc"
  subnet_name          = "${var.environment}-subnet-us-central1"
  subnet_ip_cidr_range = "10.10.0.0/24"
}

module "gke" {
  source = "../../modules/gke"

  project_id  = var.project_id
  environment = var.environment
  region      = var.region

  network_id = module.network.network_id
  subnet_id  = module.network.subnet_id
}
