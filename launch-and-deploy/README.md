# Node.js Application Deployment with Terraform and Cloud-Init

This Terraform configuration deploys a Google Cloud Compute instance with automated Node.js application setup using cloud-init.

## Features

- ✅ Automated Node.js installation via NVM
- ✅ Nginx reverse proxy configuration
- ✅ SSL certificates via Let's Encrypt
- ✅ Cloudflare DNS integration
- ✅ PM2 process management
- ✅ Firewall configuration
- ✅ Cloud-init for proper initialization

## Prerequisites

1. **Google Cloud SDK** installed and authenticated:
   ```bash
   gcloud auth application-default login
   ```

2. **Terraform** installed (version 4.25.0+ compatible)

3. **Cloudflare API Token** with DNS edit permissions for your domain

## Quick Start

1. **Clone and navigate to the directory:**
   ```bash
   cd launch-and-deploy
   ```

2. **Create terraform.tfvars file:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

3. **Edit terraform.tfvars with your values:**
   ```hcl
   cf_api_token = "your-cloudflare-api-token"
   domain_name  = "yourdomain.com"
   github_repo  = "https://github.com/yourusername/your-repo.git"
   admin_email  = "admin@yourdomain.com"
   ```

4. **Initialize and deploy:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## File Structure

```
launch-and-deploy/
├── main.tf                    # Main Terraform configuration
├── cloud-init.yaml           # Cloud-init configuration
├── setup.sh                  # Application setup script
├── terraform.tfvars.example  # Example variables file
└── README.md                 # This file
```

## Configuration Details

### Cloud-Init Integration

The setup now uses proper cloud-init configuration instead of just startup scripts:

- **cloud-init.yaml**: Defines the cloud-init configuration with package installation, user setup, and script execution
- **setup.sh**: Contains the detailed application setup logic
- **main.tf**: Terraform configuration that passes the setup script to cloud-init via user-data

### Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `cf_api_token` | Cloudflare API token (required) | `""` |
| `domain_name` | Your domain name | `"bareflux.co"` |
| `github_repo` | GitHub repository URL | `"https://github.com/sumansaurabh/task-bb.git"` |
| `admin_email` | Email for SSL certificates | `"admin@bareflux.co"` |

### What Gets Installed

1. **System packages**: curl, wget, git, build-essential, nginx, certbot, etc.
2. **Node.js**: Latest LTS version via NVM
3. **PM2**: Process manager for Node.js applications
4. **Nginx**: Reverse proxy with SSL termination
5. **Let's Encrypt**: Automatic SSL certificate generation
6. **Firewall**: UFW configured for HTTP/HTTPS traffic

## Deployment Process

1. **Cloud-init phase**: Installs packages and creates nodeuser
2. **Setup script execution**: Runs as nodeuser to install Node.js and configure application
3. **Application deployment**: Clones repository and starts with PM2
4. **SSL setup**: Obtains Let's Encrypt certificates
5. **Service configuration**: Configures auto-renewal and monitoring

## Monitoring and Management

After deployment, you can:

- **Check application status**: `pm2 status`
- **View logs**: `pm2 logs`
- **Restart application**: `pm2 restart all`
- **Check Nginx**: `sudo systemctl status nginx`
- **View cloud-init logs**: `sudo tail -f /var/log/cloud-init-output.log`

## Outputs

The Terraform configuration provides:

- `instance_external_ip`: The external IP address of the instance
- `application_url`: The HTTPS URL where your application will be accessible

## Troubleshooting

1. **Check cloud-init status**:
   ```bash
   sudo cloud-init status
   ```

2. **View cloud-init logs**:
   ```bash
   sudo cat /var/log/cloud-init-output.log
   ```

3. **Check setup script logs**:
   ```bash
   sudo journalctl -u cloud-final
   ```

4. **Verify DNS propagation**:
   ```bash
   nslookup yourdomain.com
   ```

## Security Features

- Firewall (UFW) configured to allow only SSH, HTTP, and HTTPS
- SSL certificates with automatic renewal
- Non-root user execution for application processes
- Secure service account configuration

## Cleanup

To destroy the infrastructure:

```bash
terraform destroy
```

## Support

For issues or questions, check the logs first:
- Cloud-init: `/var/log/cloud-init-output.log`
- Application: `pm2 logs`
- Nginx: `sudo journalctl -u nginx`
