resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "${var.display_name_prefix}-email"
  type         = "email"

  labels = {
    email_address = var.notification_email
  }
}

# WHY HTTP against the bare static IP, no domain/TLS: this project has no registered
# domain and issues no certificate for it, so there is nothing for an HTTPS check to
# validate against. Checking plain HTTP on the IP still proves the thing this alert
# actually cares about — is the Nginx pod up and is the Ingress routing to it — without
# taking on a domain/cert dependency just to make the check itself.
resource "google_monitoring_uptime_check_config" "ingress" {
  project      = var.project_id
  display_name = "${var.display_name_prefix}-ingress-http"
  timeout      = "10s"
  period       = "300s"

  http_check {
    path         = "/"
    port         = 80
    use_ssl      = false
    validate_ssl = false
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.ingress_ip_address
    }
  }
}

# WHY this exact filter/aggregation shape: this is the standard recipe for turning a
# per-region uptime_check/check_passed boolean metric into a single "is it failing right
# now" alert — ALIGN_NEXT_OLDER carries the last known pass/fail state forward per
# checker region, REDUCE_COUNT_FALSE counts how many regions are currently failing, and
# threshold_value = 1 with COMPARISON_GT fires as soon as at least one checker region
# reports failure.
resource "google_monitoring_alert_policy" "uptime_failure" {
  project      = var.project_id
  display_name = "${var.display_name_prefix}-ingress-uptime-failure"
  combiner     = "OR"

  conditions {
    display_name = "Ingress uptime check failing"

    condition_threshold {
      filter          = "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.check_id=\"${google_monitoring_uptime_check_config.ingress.uptime_check_id}\""
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = 1

      aggregations {
        alignment_period     = "1200s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.host"]
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  documentation {
    content   = "Uptime check against the Ingress static IP (${var.ingress_ip_address}) is failing. Check `kubectl get pods,ingress` in the affected namespace before assuming it's the load balancer."
    mime_type = "text/markdown"
  }
}

# WHY these three signals: request count and latency come from the GCLB the GKE
# Ingress provisions (loadbalancing.googleapis.com/https/*) — they're the two numbers
# that answer "is anyone hitting this and is it fast", the basic health-of-traffic view
# for a public-facing SPA. Pod restart count (kubernetes.io/container/restart_count)
# answers a different question — "is the workload itself stable" — a crash-looping pod
# can serve zero traffic and therefore show up as nothing but silence in the other two
# charts.
resource "google_monitoring_dashboard" "platform" {
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = "${var.display_name_prefix}-platform"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Ingress request count"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"loadbalancing.googleapis.com/https/request_count\" resource.type=\"https_lb_rule\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.\"url_map_name\""]
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          xPos   = 6
          width  = 6
          height = 4
          widget = {
            title = "Ingress p99 latency"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"loadbalancing.googleapis.com/https/total_latencies\" resource.type=\"https_lb_rule\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_PERCENTILE_99"
                      crossSeriesReducer = "REDUCE_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "Pod restart count"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"kubernetes.io/container/restart_count\" resource.type=\"k8s_container\" resource.label.\"cluster_name\"=\"${var.cluster_name}\""
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_DELTA"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.\"namespace_name\""]
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
      ]
    }
  })
}
