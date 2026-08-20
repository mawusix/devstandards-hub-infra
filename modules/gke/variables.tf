variable "project_id" {
  description = "GCP project ID to create the GKE Autopilot cluster in."
  type        = string
}

variable "region" {
  description = "Region for the (regional) Autopilot cluster. Autopilot clusters cannot be zonal."
  type        = string
}

variable "cluster_name" {
  description = "Name of the single shared GKE Autopilot cluster. int/pre/prod are Kubernetes namespaces inside this one cluster, not separate clusters — see platform/README.md."
  type        = string
  default     = "devstandards-hub"
}

variable "network_id" {
  description = "Self-link of the VPC to attach the cluster to (from modules/network)."
  type        = string
}

variable "subnetwork_id" {
  description = "Self-link of the subnet to attach the cluster to (from modules/network)."
  type        = string
}

variable "pods_range_name" {
  description = "Name of the subnet's secondary range to allocate pod IPs from (from modules/network)."
  type        = string
}

variable "services_range_name" {
  description = "Name of the subnet's secondary range to allocate Service ClusterIPs from (from modules/network)."
  type        = string
}

variable "release_channel" {
  description = "GKE release channel. REGULAR balances new-feature/patch cadence against stability, and is the channel Autopilot recommends by default."
  type        = string
  default     = "REGULAR"
}

variable "maintenance_start_time" {
  description = "Daily maintenance window start time, HH:MM in UTC. Default 03:00 UTC (~off-peak for a UK-based demo audience) keeps any auto-upgrade disruption away from likely demo/viva hours."
  type        = string
  default     = "03:00"
}

variable "deletion_protection" {
  description = "Whether Terraform refuses to destroy the cluster. False because this cluster is torn down after the demo; true would require a manual API flag flip before every terraform destroy, which defeats the point for a short-lived project."
  type        = bool
  default     = false
}
