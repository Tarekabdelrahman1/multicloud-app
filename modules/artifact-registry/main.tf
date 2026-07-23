resource "google_artifact_registry_repository" "docker" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  format        = "DOCKER"

  description = "${var.environment} Docker repository"

   cleanup_policies {
    id     = "keep-recent-images"
    action = "KEEP"

    most_recent_versions {
      keep_count = 10
    }
  }

  cleanup_policies {
    id     = "delete-untagged-images"
    action = "DELETE"

    condition {
      tag_state = "UNTAGGED"
    }
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}
