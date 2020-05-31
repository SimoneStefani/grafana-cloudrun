# This file contains all the interactions with Google Cloud
provider "google" {
  region      = var.region
  project     = var.project
  credentials = file("./account.json")
}

provider "google-beta" {
  region      = var.region
  project     = var.project
  credentials = file("./account.json")
}

# Enable required services on the project
resource "google_project_service" "service" {
  count   = length(var.project_services)
  project = var.project
  service = element(var.project_services, count.index)

  # Do not disable the service on destroy. On destroy, we are going to
  # destroy the project, but we need the APIs available to destroy the
  # underlying resources.
  disable_on_destroy = false
}


#
# Grafana Networking
# ------------------------------

# Setup reserved private network to connect Grafana service to DB
resource "google_compute_network" "grafana_private_network" {
  provider = google-beta

  name = "grafana-network"

  depends_on = [google_project_service.service]
}

# Create an internal global IP address for the DB
resource "google_compute_global_address" "grafana_private_ip_address" {
  provider = google-beta

  name          = "grafana-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.grafana_private_network.self_link
}

# Create a VPC connection using the internal IP and the grafana-network
resource "google_service_networking_connection" "grafana_private_vpc_connection" {
  provider = google-beta

  network                 = google_compute_network.grafana_private_network.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.grafana_private_ip_address.name]
}

# Setup a serverless VPC connector to attach to Cloud Run instance
resource "google_vpc_access_connector" "grafana_vpc_connector" {
  name          = "grafana-vpc-connector"
  region        = var.region
  ip_cidr_range = "10.8.0.0/28"
  network       = google_compute_network.grafana_private_network.name
}


#
# Grafana DB setup
# ------------------------------

resource "random_id" "db_name_suffix" {
  byte_length = 4
}

# Create a PostgreSQL database to store Grafana settings, users, etc.
# The instance exposes only a private IP accessible over grafana-network
resource "google_sql_database_instance" "grafana_db_instance" {
  name             = "grafana-db-${random_id.db_name_suffix.hex}"
  database_version = "POSTGRES_12"
  region           = var.region

  depends_on = [
    google_service_networking_connection.grafana_private_vpc_connection,
    google_project_service.service
  ]

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.grafana_private_network.self_link
    }
  }
}

# Create a database in the instance
resource "google_sql_database" "grafana_database" {
  name     = var.db_name
  instance = google_sql_database_instance.grafana_db_instance.name
}

# Create a database user for Grafana
resource "google_sql_user" "grafana_db_user" {
  name     = var.db_user
  password = var.db_password
  instance = google_sql_database_instance.grafana_db_instance.name
}


#
# Grafana service setup
# ------------------------------

# Create Cloud Run deploying a Grafana 6 container and direct all traffic
# to latest version deployed. Setup all necessary environment variables 
# and attach grafana-vpc-connector to connect to grafana-network.
resource "google_cloud_run_service" "grafana_service" {
  name     = "grafana"
  location = var.region

  depends_on = [
    google_sql_database_instance.grafana_db_instance,
    google_sql_database.grafana_database
  ]

  template {
    spec {
      containers {
        image = "marketplace.gcr.io/google/grafana6"
        env {
          name  = "GF_SERVER_HTTP_PORT"
          value = 8080
        }
        env {
          name  = "GF_DATABASE_TYPE"
          value = "postgres"
        }
        env {
          name  = "GF_DATABASE_HOST"
          value = google_sql_database_instance.grafana_db_instance.private_ip_address
        }
        env {
          name  = "GF_DATABASE_NAME"
          value = var.db_name
        }
        env {
          name  = "GF_DATABASE_USER"
          value = var.db_user
        }
        env {
          name  = "GF_DATABASE_PASSWORD"
          value = var.db_password
        }
        env {
          name  = "GF_SECURITY_ADMIN_PASSWORD"
          value = var.grafana_admin_password
        }
      }
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"        = "1"
        "run.googleapis.com/client-name"          = "terraform"
        "run.googleapis.com/vpc-access-connector" = "${google_vpc_access_connector.grafana_vpc_connector.id}"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  autogenerate_revision_name = true
}

# Create Google IAM policy to allow unauthenticated access to Cloud Run
data "google_iam_policy" "noauth" {
  binding {
    role    = "roles/run.invoker"
    members = ["allUsers"]
  }
}

# Attach IAM policy to grafana Cloud Run service
resource "google_cloud_run_service_iam_policy" "noauth" {
  location    = google_cloud_run_service.grafana_service.location
  project     = google_cloud_run_service.grafana_service.project
  service     = google_cloud_run_service.grafana_service.name
  policy_data = data.google_iam_policy.noauth.policy_data
}
