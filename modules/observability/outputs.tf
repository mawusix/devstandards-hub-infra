output "notification_channel_id" {
  description = "ID of the email notification channel."
  value       = google_monitoring_notification_channel.email.id
}

output "uptime_check_id" {
  description = "ID of the Ingress uptime check."
  value       = google_monitoring_uptime_check_config.ingress.uptime_check_id
}

output "dashboard_id" {
  description = "ID of the platform dashboard."
  value       = google_monitoring_dashboard.platform.id
}
