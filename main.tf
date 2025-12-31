# VPC Network
resource "google_compute_network" "emqx_network" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

# Subnet
resource "google_compute_subnetwork" "emqx_subnet" {
  name          = "${var.network_name}-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.emqx_network.id
}

# GCS Bucket for certificates
resource "google_storage_bucket" "certificates" {
  name     = "${var.certificate_bucket}-${var.project_id}"
  location = var.region

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true
}

# Firewall rules
resource "google_compute_firewall" "emqx_mqtts_prod" {
  name    = "emqx-mqtts-prod"
  network = google_compute_network.emqx_network.name

  allow {
    protocol = "tcp"
    ports    = [var.mqtts_prod_port]
  }

  source_ranges = var.allowed_cidr_ranges
  target_tags   = ["emqx-broker"]
}

resource "google_compute_firewall" "emqx_mqtts_dev" {
  name    = "emqx-mqtts-dev"
  network = google_compute_network.emqx_network.name

  allow {
    protocol = "tcp"
    ports    = [var.mqtts_dev_port]
  }

  source_ranges = var.allowed_cidr_ranges
  target_tags   = ["emqx-broker"]
}

resource "google_compute_firewall" "emqx_dashboard" {
  name    = "emqx-dashboard"
  network = google_compute_network.emqx_network.name

  allow {
    protocol = "tcp"
    ports    = [var.dashboard_port]
  }

  source_ranges = var.allowed_cidr_ranges
  target_tags   = ["emqx-broker"]
}

resource "google_compute_firewall" "emqx_websocket" {
  name    = "emqx-websocket"
  network = google_compute_network.emqx_network.name

  allow {
    protocol = "tcp"
    ports    = ["8083"]
  }

  source_ranges = var.allowed_cidr_ranges
  target_tags   = ["emqx-broker"]
}

resource "google_compute_firewall" "emqx_websocket_secure" {
  name    = "emqx-websocket-secure"
  network = google_compute_network.emqx_network.name

  allow {
    protocol = "tcp"
    ports    = ["8084"]
  }

  source_ranges = var.allowed_cidr_ranges
  target_tags   = ["emqx-broker"]
}

resource "google_compute_firewall" "emqx_internal" {
  name    = "emqx-internal"
  network = google_compute_network.emqx_network.name

  allow {
    protocol = "tcp"
    ports    = ["4369", "5369", "6369", "4369-4399"]
  }

  source_tags = ["emqx-broker"]
  target_tags = ["emqx-broker"]
}

resource "google_compute_firewall" "emqx_health_check" {
  name    = "emqx-health-check"
  network = google_compute_network.emqx_network.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["emqx-broker"]
}

# Firewall rule for SSH access
resource "google_compute_firewall" "emqx_ssh" {
  name    = "emqx-ssh"
  network = google_compute_network.emqx_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_cidr_ranges
  target_tags   = ["emqx-broker"]
}

# Instance template for EMQX
resource "google_compute_instance_template" "emqx_template" {
  name_prefix  = "emqx-template-"
  machine_type = var.emqx_machine_type

  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
    disk_type    = "pd-standard"
    disk_size_gb = 20
  }

  network_interface {
    network    = google_compute_network.emqx_network.id
    subnetwork = google_compute_subnetwork.emqx_subnet.id
    access_config {
      // Ephemeral public IP
    }
  }

  tags = ["emqx-broker"]

  metadata = {
    startup-script = templatefile("${path.module}/scripts/emqx-setup.sh", {
      emqx_version     = var.emqx_version
      mqtts_prod_port  = var.mqtts_prod_port
      mqtts_dev_port   = var.mqtts_dev_port
      dashboard_port   = var.dashboard_port
      certificate_bucket = "${var.certificate_bucket}-${var.project_id}"
    })
  }

  service_account {
    email  = google_service_account.emqx.email
    scopes = ["cloud-platform"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Service Account for EMQX instances
resource "google_service_account" "emqx" {
  account_id   = "emqx-instance"
  display_name = "EMQX Instance Service Account"
}

resource "google_project_iam_member" "emqx_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.emqx.email}"
}

# Managed Instance Group
resource "google_compute_instance_group_manager" "emqx_group" {
  name               = "emqx-instance-group"
  base_instance_name = "emqx"
  zone               = var.zone
  target_size        = var.emqx_instance_count

  version {
    instance_template = google_compute_instance_template.emqx_template.id
  }

  named_port {
    name = "mqtts-prod"
    port = var.mqtts_prod_port
  }

  named_port {
    name = "mqtts-dev"
    port = var.mqtts_dev_port
  }

  auto_healing_policies {
    health_check      = google_compute_region_health_check.emqx_health_check.id
    initial_delay_sec = 300
  }
}

# Health check for EMQX (HTTP check for dashboard API) - regional for NetLB
resource "google_compute_region_health_check" "emqx_health_check" {
  name   = "emqx-health-check"
  region = var.region

  http_health_check {
    port         = var.dashboard_port
    request_path = "/api/v5/status"
    response     = "200"
  }

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
}

# TCP health check for MQTT port (alternative, can be used for TCP-only checks)
resource "google_compute_health_check" "emqx_tcp_health_check" {
  name = "emqx-tcp-health-check"

  tcp_health_check {
    port = var.mqtts_prod_port
  }

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
}

# Backend service for prod (regional for regional instance group)
resource "google_compute_region_backend_service" "emqx_prod" {
  name                  = "emqx-mqtts-prod-backend"
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  region                = var.region
  # For TCP load balancers, we use HTTP health check on dashboard port
  # This verifies the instance is running and EMQX is healthy
  health_checks         = [google_compute_region_health_check.emqx_health_check.id]
  timeout_sec           = 30

  backend {
    group = google_compute_instance_group_manager.emqx_group.instance_group
  }
}

# Backend service for dev (regional for regional instance group)
resource "google_compute_region_backend_service" "emqx_dev" {
  name                  = "emqx-mqtts-dev-backend"
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  region                = var.region
  health_checks         = [google_compute_region_health_check.emqx_health_check.id]
  timeout_sec           = 30

  backend {
    group = google_compute_instance_group_manager.emqx_group.instance_group
  }
}

# Forwarding rule for prod (regional for regional backend service)
resource "google_compute_forwarding_rule" "emqx_prod" {
  name                  = "emqx-mqtts-prod-forwarding-rule"
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
  port_range            = "${var.mqtts_prod_port}-${var.mqtts_prod_port}"
  backend_service       = google_compute_region_backend_service.emqx_prod.id
  region                = var.region
}

# Forwarding rule for dev (regional for regional backend service)
resource "google_compute_forwarding_rule" "emqx_dev" {
  name                  = "emqx-mqtts-dev-forwarding-rule"
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
  port_range            = "${var.mqtts_dev_port}-${var.mqtts_dev_port}"
  backend_service       = google_compute_region_backend_service.emqx_dev.id
  region                = var.region
}

