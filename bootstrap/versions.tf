terraform {
  # WHY >= 1.9: nothing here uses a post-1.9 language feature specifically, but pinning
  # a floor keeps `terraform validate` behaviour consistent with what's documented in
  # the README's exact commands, rather than "whatever happens to be on the laptop".
  required_version = ">= 1.9"

  required_providers {
    google = {
      source = "hashicorp/google"
      # WHY an exact version, not a "~>" range: this directory is applied by hand from
      # a laptop, not from a pinned CI image. A floating range would let two different
      # people bootstrap the same project with two different provider versions and get
      # subtly different resource defaults (e.g. new fields, changed defaults) without
      # either of them noticing.
      version = "6.18.0"
    }
  }

  # WHY local, not gcs: see README "Why local state" — this directory creates the very
  # bucket that every other repo's remote state lives in, so it cannot itself depend on
  # that bucket existing yet.
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
