resource "google_container_cluster" "cluster" {
  name     = "${var.environment}-gke"
  project  = var.project_id
  location = var.zone
  network    = var.network_id
  subnetwork = var.subnet_id

  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = false
}

resource "google_container_node_pool" "primary" {
  name     = "${var.environment}-primary-pool"
  project  = var.project_id
  location = var.zone
  cluster  = google_container_cluster.cluster.name

  node_count = 1

  node_config {
    machine_type = "e2-standard-2"
    disk_type    = "pd-balanced"
    disk_size_gb = 50
    
    service_account = var.service_account_email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      environment = var.environment
    }
  }
}
