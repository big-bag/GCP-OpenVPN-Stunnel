variable "gcp_project" {}
variable "gcp_region" {}
variable "gcp_zone" {}
variable "os_username" {}
variable "os_user_key" {}
variable "gcp_image" {}
variable "gcp_min_cpu" {}

resource "google_compute_address" "static" {
  address_type = "EXTERNAL"
  name         = "ipv4-address"
  network_tier = "PREMIUM"
  project      = var.gcp_project
  region       = var.gcp_region
}

resource "google_compute_firewall" "openvpn" {
  allow {
    protocol = "tcp"
    ports    = ["1194"]
  }
  allow {
    protocol = "udp"
    ports    = ["1194"]
  }
  direction     = "INGRESS"
  name          = "allow-openvpn"
  network       = "default"
  priority      = 1005
  project       = var.gcp_project
  source_ranges = ["0.0.0.0/0"]

  // Allow traffic from everywhere to instances with these tags
  target_tags = ["openvpn"]
}

resource "google_compute_firewall" "mail" {
  allow {
    protocol = "tcp"
    ports = [
      "25",
      "993",
      "465",
    ]
  }
  direction     = "INGRESS"
  name          = "allow-mail"
  network       = "default"
  priority      = 1005
  project       = var.gcp_project
  source_ranges = ["0.0.0.0/0"]

  // Allow traffic from everywhere to instances with these tags
  target_tags = ["mail"]
}

resource "google_compute_firewall" "stunnel" {
  allow {
    protocol = "tcp"
    ports    = ["8443"]
  }
  direction     = "INGRESS"
  name          = "allow-stunnel"
  network       = "default"
  priority      = 1005
  project       = var.gcp_project
  source_ranges = ["0.0.0.0/0"]

  // Allow traffic from everywhere to instances with these tags
  target_tags = ["stunnel"]
}

resource "google_compute_firewall" "mtproto" {
  allow {
    protocol = "tcp"
    ports    = ["9443"]
  }
  direction     = "INGRESS"
  name          = "allow-mtproto"
  network       = "default"
  priority      = 1005
  project       = var.gcp_project
  source_ranges = ["0.0.0.0/0"]

  // Allow traffic from everywhere to instances with these tags
  target_tags = ["mtproto"]
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    "ssh-keys" = "${var.os_username}:${file(var.os_user_key)}"
  }
  project = var.gcp_project
}

resource "google_compute_instance" "instance-1" {
  allow_stopping_for_update = true
  boot_disk {
    auto_delete = true
    device_name = "instance-1"
    mode        = "READ_WRITE"
    initialize_params {
      image  = var.gcp_image
      labels = {}
      size   = 30
      type   = "pd-standard"
    }
  }
  can_ip_forward      = false
  deletion_protection = false
  guest_accelerator   = []
  labels              = {}
  machine_type        = "f1-micro"
  metadata            = {}
  min_cpu_platform    = var.gcp_min_cpu
  name                = "instance-1"
  network_interface {
    network            = "default"
    subnetwork         = "default"
    subnetwork_project = var.gcp_project
    access_config {
      nat_ip       = google_compute_address.static.address
      network_tier = "PREMIUM"
    }
  }
  project = var.gcp_project
  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
  }

  #    service_account {
  #        email  = "920578429975-compute@developer.gserviceaccount.com"
  #        scopes = [
  #            "https://www.googleapis.com/auth/devstorage.read_only",
  #            "https://www.googleapis.com/auth/logging.write",
  #            "https://www.googleapis.com/auth/monitoring.write",
  #            "https://www.googleapis.com/auth/service.management.readonly",
  #            "https://www.googleapis.com/auth/servicecontrol",
  #            "https://www.googleapis.com/auth/trace.append",
  #        ]
  #    }
  // Apply the firewall rule to allow external IPs to access this instance
  tags = [
    "openvpn",
    "mail",
    "stunnel",
    "mtproto",
    "http-server",
    "https-server",
  ]
  zone = var.gcp_zone
}