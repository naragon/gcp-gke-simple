terraform {
  required_version = ">= 1.10, < 2.0"
  backend "gcs" {}
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = "us-central1"
}

variable "project_id" {
  description = "Your GCP project ID."
  type        = string
}

resource "google_storage_bucket" "state" {
  name                        = "${var.project_id}-tfstate"
  location                    = "US-CENTRAL1"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  versioning {
    enabled = true
  }
  lifecycle_rule {
    condition {
      num_newer_versions = 10
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }
  lifecycle {
    prevent_destroy = true
  }
  labels = {
    environment = "lab"
    managed_by  = "terraform"
  }
}

output "state_bucket" {
  value = google_storage_bucket.state.name
}
