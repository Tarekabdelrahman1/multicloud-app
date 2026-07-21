terraform {
  backend "gcs" {
    bucket = "remote-state-project"
    prefix = "envs/dev"
  }
}
