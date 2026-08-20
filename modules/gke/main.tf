# WHY one Autopilot cluster for all three environments: see platform/README.md for the
# full reasoning. In short — three GKE clusters (even Autopilot's small per-cluster
# baseline) plus three regional control planes is real, avoidable spend on a free-trial
# budget when Kubernetes namespaces + RBAC already give int/pre/prod workload isolation
# that's more than sufficient for a portfolio/demo project with no compliance
# requirement to physically separate environments.
resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region

  enable_autopilot = true

  # WHY false: cluster and its dependents get destroyed after the demo (see
  # var.deletion_protection description) — this must stay in sync with that variable so
  # `terraform destroy` isn't silently blocked by a second, separate protection flag.
  deletion_protection = var.deletion_protection

  network    = var.network_id
  subnetwork = var.subnetwork_id

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # WHY private nodes + a PUBLIC control plane endpoint with no authorized networks:
  # nodes get no external IP (all node/pod traffic, including image pulls, stays inside
  # the VPC + Private Google Access — see modules/network's "no Cloud NAT" comment).
  # The control plane endpoint, though, is deliberately left public and unrestricted.
  # GitHub-hosted Actions runners have no stable IP range to allowlist in
  # master_authorized_networks — Microsoft/GitHub rotates the runner pool continuously,
  # and self-hosting a runner (or a bastion) just to get a stable IP is infrastructure
  # this demo project doesn't otherwise need. Access control is therefore enforced at
  # the identity layer instead of the network layer: only WIF-federated, RBAC-authorized
  # identities (ci-infra-sa via Terraform, ci-app-sa/deploy workflow via kubectl/Helm)
  # can do anything once connected. This is an accepted tradeoff, not an oversight — a
  # production system handling sensitive workloads would instead run apply/deploy from
  # a fixed-IP runner (self-hosted, or a GitHub Actions larger-runner in a static
  # egress range) and lock master_authorized_networks_config down to it.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    # WHY no master_authorized_networks_config block at all here (as opposed to an
    # empty one): omitting the block entirely leaves the public endpoint reachable from
    # any IP, which is the "no authorized networks" requirement above. An *empty*
    # master_authorized_networks_config block is a different thing — it enables the
    # authorized-networks feature with zero entries, which locks the public endpoint out
    # to everyone. That's the opposite of what's wanted here.
  }

  release_channel {
    channel = var.release_channel
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }
  }

  # WHY no node_pool / node_config / machine_type here: Autopilot manages node pools,
  # machine shapes, and sizing itself per-workload. Setting any of those fields is
  # invalid on an Autopilot cluster (they're Standard-mode-only) and would fail apply.
}
