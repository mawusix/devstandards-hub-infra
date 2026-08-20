# WHY count instead of unconditionally creating this: see create_budget's description
# in variables.tf — budget creation needs a billing-account-level role that a free-trial
# account's default credentials don't always carry, even when every other resource in
# this directory applies fine under project-level roles. Guarding it behind a flag
# means one missing permission doesn't block the rest of bootstrap.
resource "google_billing_budget" "monthly" {
  count = var.create_budget ? 1 : 0

  billing_account = var.billing_account_id
  display_name    = "${var.project_id}-monthly-budget"

  budget_filter {
    # WHY scoped to this one project: the billing account could in principle have other
    # projects on it later. Scoping the filter means this alert always tracks
    # devops-bpp's spend specifically, not the whole account's.
    projects               = ["projects/${data.google_project.this.number}"]
    credit_types_treatment = "EXCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency_code
      units         = tostring(var.budget_amount)
    }
  }

  # WHY three separate blocks instead of a list: google_billing_budget's schema takes
  # threshold_rules as repeated blocks, one per percentage, each firing its own alert
  # email to Billing Account Administrators once current spend crosses that fraction of
  # amount.
  threshold_rules {
    threshold_percent = 0.5
  }

  threshold_rules {
    threshold_percent = 0.9
  }

  threshold_rules {
    threshold_percent = 1.0
  }

  depends_on = [google_project_service.this]
}
