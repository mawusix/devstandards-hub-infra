output "network_id" {
  description = "Self-link of the VPC, for wiring into google_container_cluster.network."
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "Name of the VPC."
  value       = google_compute_network.vpc.name
}

output "subnetwork_id" {
  description = "Self-link of the subnet, for wiring into google_container_cluster.subnetwork."
  value       = google_compute_subnetwork.primary.id
}

output "pods_range_name" {
  description = "Name of the secondary range GKE allocates pod IPs from."
  value       = google_compute_subnetwork.primary.secondary_ip_range[0].range_name
}

output "services_range_name" {
  description = "Name of the secondary range GKE allocates Service ClusterIPs from."
  value       = google_compute_subnetwork.primary.secondary_ip_range[1].range_name
}

output "ingress_ip_address" {
  description = "Reserved global static external IP address, for the Ingress annotation and the uptime check."
  value       = google_compute_global_address.ingress.address
}

output "ingress_ip_name" {
  description = "Name of the reserved global address, for the kubernetes.io/ingress.global-static-ip-name annotation Helm will set later."
  value       = google_compute_global_address.ingress.name
}