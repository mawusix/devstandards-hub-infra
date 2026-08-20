variable "project_id" {
  description = "GCP project ID to create monitoring resources in."
  type        = string
}

variable "notification_email" {
  description = "Email address that receives the uptime-failure alert."
  type        = string
}

variable "ingress_ip_address" {
  description = "Static external IP (from modules/network) that the uptime check polls over HTTP."
  type        = string
}

variable "cluster_name" {
  description = "GKE cluster name, used to scope the dashboard's pod-restart-count widget to this cluster."
  type        = string
}

variable "display_name_prefix" {
  description = "Prefix applied to the names of monitoring resources created here, so they're identifiable in the console alongside anything else in the project."
  type        = string
  default     = "devstandards-hub"
}
