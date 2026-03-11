provider "google" {
  project = local.project_id
  region  = local.region
  zone    = local.zone
}
