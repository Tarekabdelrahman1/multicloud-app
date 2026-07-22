output "gke_service_account_email" {
  value = google_service_account.gke.email
}

output "gke_service_account_id" {
  value = google_service_account.gke.id
}
