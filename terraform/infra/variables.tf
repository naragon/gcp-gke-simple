variable "project_id" {
  description = "Your GCP project ID; must match PROJECT_ID used during bootstrap."
  type        = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "admin_cidr" {
  description = "Trusted operator IPv4 CIDR allowed to access the Kubernetes API. Never use 0.0.0.0/0."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && try(tonumber(split("/", var.admin_cidr)[1]) >= 24, false)
    error_message = "Use a narrow IPv4 CIDR (/24 or smaller), preferably your public IP /32."
  }
}

variable "node_machine_type" {
  description = "e2-small is tight but suitable for this tiny demo; use e2-medium if workloads outgrow it."
  type        = string
  default     = "e2-small"
}

variable "deletion_protection" {
  description = "Disable and apply before intentionally destroying the lab."
  type        = bool
  default     = true
}
