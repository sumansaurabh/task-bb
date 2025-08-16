# This code is compatible with Terraform 4.25.0 and versions that are backward compatible to 4.25.0.
# For information about validating this Terraform code, see https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/google-cloud-platform-build#format-and-validate-the-configuration

resource "google_compute_instance" "instance-20250816-053549" {
  boot_disk {
    auto_delete = true
    device_name = "instance-20250816-053549"

    initialize_params {
      image = "projects/debian-cloud/global/images/debian-12-bookworm-v20250812"
      size  = 10
      type  = "pd-balanced"
    }

    mode = "READ_WRITE"
  }

  can_ip_forward      = false
  deletion_protection = false
  enable_display      = false

  labels = {
    goog-ec-src           = "vm_add-tf"
    goog-ops-agent-policy = "v2-x86-template-1-4-0"
  }

  machine_type = "e2-medium"

  metadata = {
    enable-osconfig = "TRUE"
  }

  name = "instance-20250816-053549"

  network_interface {
    access_config {
      network_tier = "PREMIUM"
    }

    queue_count = 0
    stack_type  = "IPV4_ONLY"
    subnetwork  = "projects/penify-prod/regions/us-central1/subnetworks/default"
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
    provisioning_model  = "STANDARD"
  }

  service_account {
    email  = "865238481351-compute@developer.gserviceaccount.com"
    scopes = ["https://www.googleapis.com/auth/devstorage.read_only", "https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/monitoring.write", "https://www.googleapis.com/auth/service.management.readonly", "https://www.googleapis.com/auth/servicecontrol", "https://www.googleapis.com/auth/trace.append"]
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = false
    enable_vtpm                 = true
  }

  tags = ["web-server"]

  zone = "us-central1-c"
}

provider "google" {
  # Use Application Default Credentials (ADC) instead of service account key file
  # Run: gcloud auth application-default login
  project = "penify-prod"
  region  = "us-central1"
}


// Firewall rule to allow HTTP (80) and HTTPS (443) to instances tagged with "web-server".
resource "google_compute_firewall" "allow-http-https" {
  name    = "allow-http-https"
  project = "penify-prod"

  network = "https://www.googleapis.com/compute/v1/projects/penify-prod/global/networks/default"

  direction    = "INGRESS"
  priority     = 1000
  description  = "Allow HTTP and HTTPS from the internet to web-server instances"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]

  target_tags = ["web-server"]
}
