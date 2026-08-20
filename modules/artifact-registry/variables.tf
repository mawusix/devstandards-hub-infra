variable "project_id" {
  description = "GCP project ID to create the Artifact Registry repository in."
  type        = string
}

variable "region" {
  description = "Region for the repository. Docker image pulls from GKE nodes stay fast/cheap when this matches the cluster's region."
  type        = string
}

variable "repository_id" {
  description = "Name of the Docker repository, and the path segment CI pushes images to (<region>-docker.pkg.dev/<project>/<repository_id>/<image>)."
  type        = string
  default     = "devstandards-hub"
}

variable "keep_recent_count" {
  description = "Number of most-recent image versions the cleanup policy always keeps, regardless of age."
  type        = number
  default     = 10
}

variable "delete_untagged_older_than_days" {
  description = "Age in days after which untagged image versions become eligible for deletion by the cleanup policy."
  type        = number
  default     = 7
}