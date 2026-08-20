variable "project_id" {
  description = "GCP project ID that all platform resources are created in."
  type        = string
}

variable "region" {
  description = "Region for every regional resource this root module creates (subnet, GKE cluster, Artifact Registry repo)."
  type        = string
  default     = "europe-west2"
}

variable "network_name" {
  description = "Name of the custom-mode VPC."
  type        = string
  default     = "devstandards-hub-vpc"
}

variable "subnet_cidr" {
  description = "Primary IP range of the single regional subnet."
  type        = string
  default     = "10.0.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary range for GKE pod IPs."
  type        = string
  default     = "10.4.0.0/14"
}

variable "services_cidr" {
  description = "Secondary range for GKE Service ClusterIPs."
  type        = string
  default     = "10.8.0.0/20"
}

variable "artifact_registry_repository_id" {
  description = "Name of the Artifact Registry Docker repository."
  type        = string
  default     = "devstandards-hub"
}

variable "cluster_name" {
  description = "Name of the single shared GKE Autopilot cluster backing all three environment namespaces (int/pre/prod)."
  type        = string
  default     = "devstandards-hub"
}

variable "gke_release_channel" {
  description = "GKE release channel."
  type        = string
  default     = "REGULAR"
}

variable "gke_maintenance_start_time" {
  description = "Daily maintenance window start time, HH:MM in UTC."
  type        = string
  default     = "03:00"
}

variable "gke_deletion_protection" {
  description = "Whether Terraform refuses to destroy the cluster. Kept false: this cluster is destroyed after the demo."
  type        = bool
  default     = false
}

# WHY this has a default, unlike bootstrap's ungated variables (project_id,
# github_owner, billing_account_id): those gate something dangerous if wrong — this is
# just an alert destination. terraform-apply.yml runs `apply -auto-approve`
# non-interactively with no human present to type a value in, so a required variable
# with no default would simply fail every CI apply. Override with
# TF_VAR_notification_email (or a GitHub Actions repo variable wired into the workflow)
# if the alert should go somewhere other than the project owner.
variable "notification_email" {
  description = "Email address that receives the uptime-failure alert."
  type        = string
  default     = "ameteweem@gmail.com"
}
