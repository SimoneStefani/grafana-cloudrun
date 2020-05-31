# This file contains all the interactions with Grafana
provider "grafana" {
  url  = google_cloud_run_service.grafana_service.status[0].url
  auth = "admin:${var.grafana_admin_password}"
}

# Create a new organization in Grafana
resource "grafana_organization" "grafana_org" {
  name         = "TechCoorp"
  admin_user   = "admin"
  create_users = true
}
