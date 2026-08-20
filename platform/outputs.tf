output "cluster_name" {
  description = "GKE Autopilot cluster name. Pass to `gcloud container clusters get-credentials` in the deploy workflow."
  value       = module.gke.cluster_name
}

output "cluster_location" {
  description = "Region the cluster runs in. Pass alongside cluster_name to `gcloud container clusters get-credentials --region`."
  value       = module.gke.cluster_location
}

output "artifact_registry_url" {
  description = "Full Artifact Registry repository path CI pushes images to."
  value       = module.artifact_registry.repository_url
}

output "ingress_ip" {
  description = "Reserved global static external IP. Set as the kubernetes.io/ingress.global-static-ip-name target (via module.network's ingress_ip_name, surfaced through the deploy workflow) when Helm creates the Ingress."
  value       = module.network.ingress_ip_address
}
