variable "project_id" {
  description = "GCP project ID to create the VPC, subnet, and static IP in."
  type        = string
}

variable "region" {
  description = "Region for the single subnet and the resources that reference it (e.g. GKE)."
  type        = string
}

variable "network_name" {
  description = "Name of the custom-mode VPC."
  type        = string
  default     = "devstandards-hub-vpc"
}

variable "subnet_cidr" {
  description = "Primary IP range of the single regional subnet, sized for node/pod-adjacent IPs GKE allocates directly (not pod/service IPs, which come from the secondary ranges below)."
  type        = string
  default     = "10.0.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary range for GKE pod IPs (VPC-native/alias-IP cluster). Sized large (/14) because Autopilot allocates a /24 per node by default and this is a shared demo cluster, not a capacity-planned one."
  type        = string
  default     = "10.4.0.0/14"
}

variable "services_cidr" {
  description = "Secondary range for GKE Service ClusterIPs (VPC-native/alias-IP cluster)."
  type        = string
  default     = "10.8.0.0/20"
}