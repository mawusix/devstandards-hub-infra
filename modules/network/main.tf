# WHY custom-mode, not the default network: the GCP default network auto-creates one
# subnet per region worldwide plus permissive default firewall rules (default-allow-
# internal, default-allow-ssh/rdp/icmp from 0.0.0.0/0). None of that is wanted for a
# single-region GKE Autopilot platform — custom mode starts with zero subnets and zero
# implicit firewall rules, so the only network surface that exists is the one subnet
# defined below.
resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = var.network_name
  auto_create_subnetworks = false
}

# WHY one subnet, one region: there is one GKE Autopilot cluster (europe-west2) backing
# all three environments as namespaces — see platform/README.md. A multi-region network
# would be provisioning for a topology this project doesn't have.
resource "google_compute_subnetwork" "primary" {
  project       = var.project_id
  name          = "${var.network_name}-${var.region}"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr

  # WHY required: GKE Autopilot is VPC-native (alias IP) only — it has no route-based
  # networking mode. Pods and Services each need their own secondary range distinct from
  # the primary (node) range so the three ranges never overlap.
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  # WHY true: this is what lets nodes with no external IP (private nodes, see
  # modules/gke) reach Google APIs and Artifact Registry to pull images, without a NAT
  # gateway. See the "no Cloud NAT" comment below for the full reasoning.
  private_ip_google_access = true
}

# WHY no Cloud NAT: Cloud NAT exists to give private nodes a path to the general
# internet. This SPA's pods make zero outbound calls of their own (no backend, no
# third-party APIs, no telemetry) — the *only* egress traffic private nodes generate is
# pulling container images from Artifact Registry, and Artifact Registry is a Google
# API reachable via Private Google Access (enabled on the subnet above), not the public
# internet. Cloud NAT would therefore sit there provisioned and unused, at a real
# recurring cost (~$32/month for the NAT gateway itself, before any data processing
# charges). Omitting it saves that cost with no loss of functionality.
#
# This reasoning breaks the moment the app gains any real outbound dependency (a
# third-party API, an SMTP relay, npm/apt installs at runtime, etc.) — at that point
# Cloud NAT (or a proxy) becomes required, not optional.

# WHY global, not regional: this IP is for the GKE Ingress (a global external HTTP(S)
# Load Balancer, which GKE's Ingress controller provisions), and a global forwarding
# rule requires a global address. Reserving it here (rather than letting the Ingress
# controller allocate an ephemeral one) means the address survives the Ingress object
# being deleted/recreated by Helm, and it's the value platform/ outputs as ingress_ip.
resource "google_compute_global_address" "ingress" {
  project      = var.project_id
  name         = "${var.network_name}-ingress-ip"
  address_type = "EXTERNAL"
}