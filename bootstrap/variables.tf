# WHY no defaults on project_id / github_owner / billing_account_id: each one gates
# something dangerous if wrong (which project gets billed, who can assume the CI
# service accounts, which billing account gets an alert). Forcing an explicit value in
# terraform.tfvars means a blank `terraform apply` fails fast instead of silently
# doing the wrong thing against a default that happened to be lying around.

variable "project_id" {
  description = "GCP project ID that all bootstrap resources are created in."
  type        = string
}

variable "github_owner" {
  description = "GitHub organisation or user that owns the repos allowed to federate via Workload Identity (devstandards-hub and devstandards-hub-infra both live under this owner)."
  type        = string
}

variable "billing_account_id" {
  description = "Billing account ID, format XXXXXX-XXXXXX-XXXXXX, that the budget alert is attached to."
  type        = string
}

variable "region" {
  description = "Region used for regional resources created by bootstrap (currently just the GCS state bucket)."
  type        = string
  default     = "europe-west2"
}

variable "state_bucket_name" {
  description = "Name of the GCS bucket that holds remote Terraform state for the other repos/modules. Leave null to derive it from project_id — GCP project IDs are already globally unique, so the derived bucket name is very likely available too, without needing a random suffix."
  type        = string
  default     = null
}

variable "state_bucket_noncurrent_version_count" {
  description = "Number of noncurrent (overwritten) versions of each state object the lifecycle rule keeps before deleting the oldest ones. Versioning alone would retain every historical state version forever."
  type        = number
  default     = 5
}

variable "create_budget" {
  description = "Whether to create the billing budget and threshold alert. Guarded behind this flag because creating a budget needs a billing-account-level role (e.g. Billing Account Costs Manager), which a free-trial account's owner does not always hold on their default credentials even when they can do everything else in this directory. If apply fails on the budget resource with a permission error, set this to false, apply everything else, and create the budget manually in the console instead."
  type        = bool
  default     = true
}

variable "budget_amount" {
  description = "Budget amount, denominated in budget_currency_code, that the 50/90/100% threshold alerts are calculated against."
  type        = number
  default     = 50
}

variable "budget_currency_code" {
  description = "ISO 4217 currency code for budget_amount. Must match the billing account's own currency exactly — google_billing_budget rejects a mismatched currency at apply time. A UK free-trial billing account is typically GBP even though trial credit is sometimes displayed with a $ sign."
  type        = string
  default     = "GBP"
}
