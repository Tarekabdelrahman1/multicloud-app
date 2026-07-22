output "cluster_name" {
  value = google_container_cluster.cluster.name
}

output "cluster_id" {
  value = google_container_cluster.cluster.id
}

output "cluster_endpoint" {
  value     = google_container_cluster.cluster.endpoint
  sensitive = true
}
