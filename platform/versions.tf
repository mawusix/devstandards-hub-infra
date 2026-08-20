terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.18.0"
    }
  }

  # WHY gcs, and why bucket/prefix are literal strings, not variables: backend blocks
  # are read before any variable is resolved, so Terraform forbids interpolation here —
  # this has to match bootstrap's `state_bucket_name` output (devops-bpp-tfstate)
  # exactly, by hand. "platform" as the prefix keeps this root module's state
  # (network/gke/artifact-registry/observability) in its own object path, distinct from
  # any other module or root that shares the same bucket in future.
  backend "gcs" {
    bucket = "devops-bpp-tfstate"
    prefix = "platform"
  }
}

# WHY no kubernetes/helm provider block here: configuring a Kubernetes/Helm provider
# needs a live cluster endpoint + credentials to talk to, but this same apply is what
# creates that cluster. On a first-ever apply the cluster doesn't exist yet when
# Terraform reads the provider config, which is a well-known chicken-and-egg failure
# mode for any root module that both creates a GKE cluster and configures a provider
# against it. Namespaces and workloads are created separately, by the deploy workflow's
# Helm step against the cluster this module outputs — see README.md.
provider "google" {
  project = var.project_id
  region  = var.region
}
