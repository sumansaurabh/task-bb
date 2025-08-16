# Variables for configuration
variable "cf_api_token" {
  description = "Cloudflare API token"
  type        = string
  default     = ""
  sensitive   = true
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "bareflux.co"
}

variable "github_repo" {
  description = "GitHub repository URL"
  type        = string
  default     = "https://github.com/sumansaurabh/task-bb.git"
}

variable "admin_email" {
  description = "Admin email for SSL certificates"
  type        = string
  default     = "admin@bareflux.co"
}

# Generate a short random id for resource naming (used for boot disk device_name)
resource "random_id" "device" {
  byte_length = 4
}

# This code is compatible with Terraform 4.25.0 and versions that are backward compatible to 4.25.0.
# For information about validating this Terraform code, see https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/google-cloud-platform-build#format-and-validate-the-configuration

resource "google_compute_instance" "blackbox-instance" {
  boot_disk {
    auto_delete = true
    device_name = "blackbox-${random_id.device.hex}"

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
    # Use cloud-init user-data for proper initialization
    user-data = templatefile("${path.module}/cloud-init.yaml", {
      setup_script = base64encode(file("${path.module}/setup.sh"))
      cf_api_token = var.cf_api_token
      domain_name  = var.domain_name
      github_repo  = var.github_repo
      admin_email  = var.admin_email
    })
  }

  name = "blackbox-${random_id.device.hex}"

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

# Note: Google Ops Agent policy module removed to avoid conflicts
# The instance is already labeled with "goog-ops-agent-policy" = "v2-x86-template-1-4-0"
# which will automatically apply the existing ops agent policy in the project

provider "google" {
  # Use Application Default Credentials (ADC) instead of service account key file
  # Run: gcloud auth application-default login
  project = "penify-prod"
  region  = "us-central1"
}

# Output the external IP address
output "instance_external_ip" {
  description = "External IP address of the compute instance"
  value       = google_compute_instance.blackbox-instance.network_interface[0].access_config[0].nat_ip
}

output "application_url" {
  description = "URL where the application will be accessible"
  value       = "https://${var.domain_name}"
}

# Helpful SSH command outputs
output "gcloud_ssh_command_nodeuser" {
  description = "gcloud command to SSH into the instance as the 'nodeuser' created by cloud-init"
  value       = "gcloud compute ssh nodeuser@blackbox-${random_id.device.hex} --zone us-central1-c --project penify-prod"
}

output "gcloud_ssh_command_default_user" {
  description = "gcloud command to SSH into the instance as your local user (gcloud will map keys)"
  value       = "gcloud compute ssh blackbox-${random_id.device.hex} --zone us-central1-c --project penify-prod"
}

output "instance_name" {
  description = "Name of the created instance"
  value       = "blackbox-${random_id.device.hex}"
}
