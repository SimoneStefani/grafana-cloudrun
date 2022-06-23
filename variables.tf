terraform {
  required_version = ">= 1.2"

  required_providers {
    grafana = {
      source = "grafana/grafana"
      version = "1.22.0"
    }
  }
}

variable "region" {
  type        = string
  default     = "europe-west1"
  description = "Region in which to create the service."
}

variable "project" {
  type        = string
  default     = ""
  description = "Project ID where Terraform is authenticated will generate all the resources."
}

variable "project_services" {
  type = list(string)
  default = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "servicenetworking.googleapis.com",
    "vpcaccess.googleapis.com",
    "sql-component.googleapis.com",
    "sqladmin.googleapis.com",
    "run.googleapis.com",
    "iam.googleapis.com",
  ]
  description = "List of services to enable on the project."
}

variable "db_name" {
  type        = string
  default     = "grafana"
  description = "Name of the database used by grafana."
}


variable "db_user" {
  type        = string
  default     = "grafana"
  description = "Name of the user grafana connects to the SQL database with."
}

variable "db_password" {
  type        = string
  default     = ""
  description = "Password of the grafana user in the SQL database."
}

variable "grafana_admin_password" {
  type        = string
  default     = ""
  description = "Password of the admin user in Grafana."
}
