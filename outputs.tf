output "load_balancer_ip_prod" {
  description = "External IP address of the prod MQTT load balancer"
  value       = google_compute_forwarding_rule.emqx_prod.ip_address
}

output "load_balancer_ip_dev" {
  description = "External IP address of the dev MQTT load balancer"
  value       = google_compute_forwarding_rule.emqx_dev.ip_address
}

output "emqx_instance_group" {
  description = "EMQX instance group name"
  value       = google_compute_instance_group_manager.emqx_group.name
}

output "certificate_bucket" {
  description = "GCS bucket name for certificates"
  value       = google_storage_bucket.certificates.name
}

output "network_name" {
  description = "VPC network name"
  value       = google_compute_network.emqx_network.name
}

output "dashboard_access_info" {
  description = "Information about accessing EMQX dashboard"
  value = {
    note = "Access dashboard via: http://<instance-ip>:${var.dashboard_port}"
    default_username = "admin"
    default_password = "public"
    change_password = "Change default password immediately after first login"
  }
}

