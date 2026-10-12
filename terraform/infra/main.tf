locals {
  name = "gke-lab"
  services = toset([
    "compute.googleapis.com", "container.googleapis.com", "artifactregistry.googleapis.com",
    "iam.googleapis.com", "logging.googleapis.com", "monitoring.googleapis.com", "storage.googleapis.com",
  ])
}

resource "google_project_service" "apis" {
  for_each           = local.services
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_network" "lab" {
  name                    = local.name
  auto_create_subnetworks = false
  depends_on              = [google_project_service.apis]
}

resource "google_compute_subnetwork" "lab" {
  name                     = local.name
  region                   = var.region
  network                  = google_compute_network.lab.id
  ip_cidr_range            = "10.10.0.0/24"
  private_ip_google_access = true
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/16"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.30.0.0/20"
  }
}

resource "google_compute_address" "ingress" {
  name         = "${local.name}-ingress"
  region       = var.region
  address_type = "EXTERNAL"
  depends_on   = [google_project_service.apis]
}

resource "google_artifact_registry_repository" "app" {
  location      = var.region
  repository_id = "hello"
  format        = "DOCKER"
  description   = "Private, immutable Hello world images"
  docker_config {
    immutable_tags = true
  }
  cleanup_policy_dry_run = false
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 5
    }
  }
  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      older_than = "2592000s"
      # Immutable tagged releases cannot be deleted by cleanup policies.
      tag_state = "UNTAGGED"
    }
  }
  depends_on = [google_project_service.apis]
}

resource "google_service_account" "nodes" {
  account_id   = "gke-lab-nodes"
  display_name = "GKE lab nodes (no keys)"
  depends_on   = [google_project_service.apis]
}

resource "google_project_iam_member" "nodes" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_artifact_registry_repository_iam_member" "pull" {
  location   = google_artifact_registry_repository.app.location
  repository = google_artifact_registry_repository.app.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "lab" {
  name                     = local.name
  location                 = var.zone
  network                  = google_compute_network.lab.id
  subnetwork               = google_compute_subnetwork.lab.id
  networking_mode          = "VPC_NATIVE"
  datapath_provider        = "ADVANCED_DATAPATH"
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = var.deletion_protection
  enable_shielded_nodes    = true

  # GKE reports the surviving pool as node_config after deleting the bootstrap
  # pool. Only the separate node-pool resource should manage real node settings.
  lifecycle {
    ignore_changes = [node_config]
  }

  # Also harden the short-lived bootstrap pool, then delete it.
  node_config {
    machine_type    = var.node_machine_type
    disk_size_gb    = 20
    disk_type       = "pd-standard"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    metadata        = { disable-legacy-endpoints = "true" }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  release_channel {
    channel = "REGULAR"
  }
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false
    cidr_blocks {
      cidr_block   = var.admin_cidr
      display_name = "operator"
    }
  }
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  addons_config {
    http_load_balancing {
      disabled = true
    }
    # This stateless lab uses no persistent volumes; save node memory and pods.
    gce_persistent_disk_csi_driver_config {
      enabled = false
    }
  }
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = false
    }
  }
  maintenance_policy {
    daily_maintenance_window {
      start_time = "05:00"
    }
  }
  depends_on = [google_project_iam_member.nodes, google_artifact_registry_repository_iam_member.pull]
}

resource "google_container_node_pool" "spot" {
  name       = "spot"
  location   = var.zone
  cluster    = google_container_cluster.lab.name
  node_count = 2
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  upgrade_settings {
    max_surge       = 0
    max_unavailable = 1
  }
  node_config {
    spot            = true
    machine_type    = var.node_machine_type
    disk_size_gb    = 20
    disk_type       = "pd-standard"
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    metadata        = { disable-legacy-endpoints = "true" }
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    labels = { environment = "lab" }
  }
}
