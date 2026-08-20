module "network" {
  source = "../modules/network"

  project_id    = var.project_id
  region        = var.region
  network_name  = var.network_name
  subnet_cidr   = var.subnet_cidr
  pods_cidr     = var.pods_cidr
  services_cidr = var.services_cidr
}

module "artifact_registry" {
  source = "../modules/artifact-registry"

  project_id    = var.project_id
  region        = var.region
  repository_id = var.artifact_registry_repository_id
}

module "gke" {
  source = "../modules/gke"

  project_id             = var.project_id
  region                 = var.region
  cluster_name           = var.cluster_name
  network_id             = module.network.network_id
  subnetwork_id          = module.network.subnetwork_id
  pods_range_name        = module.network.pods_range_name
  services_range_name    = module.network.services_range_name
  release_channel        = var.gke_release_channel
  maintenance_start_time = var.gke_maintenance_start_time
  deletion_protection    = var.gke_deletion_protection
}

module "observability" {
  source = "../modules/observability"

  project_id         = var.project_id
  notification_email = var.notification_email
  ingress_ip_address = module.network.ingress_ip_address
  cluster_name       = module.gke.cluster_name
}
