output "deployment" {
  description = "Non-secret configuration consumed directly by Ansible."
  value = {
    project_id      = var.project_id
    region          = var.region
    zone            = var.zone
    cluster_name    = google_container_cluster.lab.name
    ingress_ip      = google_compute_address.ingress.address
    ingress_ip_name = google_compute_address.ingress.name
    registry_host   = "${var.region}-docker.pkg.dev"
    image_name      = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}/hello"
  }
}
