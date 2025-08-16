#!/bin/bash

#############################################################################
# Automated Node.js + Cloudflare + HTTPS Setup Script
# 
# This script sets up a complete production environment with:
# - Node.js via NVM
# - Nginx reverse proxy
# - Let's Encrypt SSL certificates with auto-renewal
# - Cloudflare DNS integration
# - PM2 process management
#
# Usage:
#   export CF_API_TOKEN="your-token"
#   export DOMAIN_NAME="your-domain.com"
#   export SERVER_IP="your-ip"
#   export GITHUB_REPO="https://github.com/user/repo.git"
#   export EMAIL="admin@domain.com"
#   curl -fsSL https://raw.githubusercontent.com/your-repo/setup.sh | bash
#############################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error_exit "This script should not be run as root. Please run as a regular user with sudo privileges."
    fi
}

# Validate environment variables
validate_env() {
    log_info "Validating environment variables..."
    
    # Set defaults if not provided
    CF_API_TOKEN="${CF_API_TOKEN:-}"
    DOMAIN_NAME="${DOMAIN_NAME:-bareflux.co}"
    SERVER_IP="${SERVER_IP:-$(curl -s ifconfig.me)}"
    GITHUB_REPO="${GITHUB_REPO:-https://github.com/sumansaurabh/task-bb.git}"
    EMAIL="${EMAIL:-admin@${DOMAIN_NAME}}"
    
    # Validate required variables
    if [[ -z "$CF_API_TOKEN" ]]; then
        error_exit "CF_API_TOKEN environment variable is required"
    fi
    
    if [[ -z "$DOMAIN_NAME" ]]; then
        error_exit "DOMAIN_NAME environment variable is required"
    fi
    
    log_success "Environment variables validated"
    log_info "Domain: $DOMAIN_NAME"
    log_info "Server IP: $SERVER_IP"
    log_info "Repository: $GITHUB_REPO"
}

# Update system packages
update_system() {
    log_info "Updating system packages..."
    sudo apt-get update -y
    sudo apt-get upgrade -y
    log_success "System packages updated"
}

# Install required packages
install_packages() {
    log_info "Installing required packages..."
    sudo apt-get install -y \
        curl \
        wget \
        git \
        build-essential \
        nginx \
        certbot \
        python3-certbot-nginx \
        jq \
        ufw \
        ca-certificates \
        gnupg \
        lsb-release
    log_success "Required packages installed"
}

# Configure firewall
setup_firewall() {
    log_info "Configuring firewall..."
    sudo ufw --force enable
    sudo ufw allow ssh
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    log_success "Firewall configured"
}

# Install NVM and Node.js
install_node() {
    log_info "Installing NVM and Node.js..."
    
    # Install NVM
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    
    # Load NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    
    # Install Node.js
    nvm install v20.19.4
    nvm alias default v20.19.4
    nvm use v20.19.4
    
    # Install PM2 globally
    npm install -g pm2
    
    log_success "Node.js $(node --version) and PM2 installed"
}

# Update Cloudflare DNS records
update_cloudflare_dns() {
    log_info "Updating Cloudflare DNS records..."
    
    # Get Zone ID
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN_NAME}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')
    
    if [[ "$ZONE_ID" == "null" || -z "$ZONE_ID" ]]; then
        error_exit "Could not find zone for domain ${DOMAIN_NAME}. Please check your domain and API token."
    fi
    
    log_info "Zone ID: $ZONE_ID"
    
    # Function to create or update DNS record
    update_dns_record() {
        local record_name="$1"
        local record_type="A"
        local record_content="$SERVER_IP"
        
        # Check if record exists
        RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=${record_type}&name=${record_name}" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" | jq -r '.result[0].id')
        
        if [[ "$RECORD_ID" == "null" || -z "$RECORD_ID" ]]; then
            # Create new record
            RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
                -H "Authorization: Bearer ${CF_API_TOKEN}" \
                -H "Content-Type: application/json" \
                --data "{\"type\":\"${record_type}\",\"name\":\"${record_name}\",\"content\":\"${record_content}\",\"ttl\":300}")
            
            SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
            if [[ "$SUCCESS" == "true" ]]; then
                log_success "Created A record for ${record_name}"
            else
                log_error "Failed to create A record for ${record_name}: $(echo "$RESPONSE" | jq -r '.errors[0].message')"
            fi
        else
            # Update existing record
            RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
                -H "Authorization: Bearer ${CF_API_TOKEN}" \
                -H "Content-Type: application/json" \
                --data "{\"type\":\"${record_type}\",\"name\":\"${record_name}\",\"content\":\"${record_content}\",\"ttl\":300}")
            
            SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
            if [[ "$SUCCESS" == "true" ]]; then
                log_success "Updated A record for ${record_name}"
            else
                log_error "Failed to update A record for ${record_name}: $(echo "$RESPONSE" | jq -r '.errors[0].message')"
            fi
        fi
    }
    
    # Update DNS records
    update_dns_record "$DOMAIN_NAME"
    update_dns_record "www.$DOMAIN_NAME"
    
    log_info "Waiting for DNS propagation (60 seconds)..."
    sleep 60
}

# Setup application
setup_application() {
    log_info "Setting up application..."
    
    # Clone repository
    if [[ -d "$HOME/app" ]]; then
        rm -rf "$HOME/app"
    fi
    
    git clone "$GITHUB_REPO" "$HOME/app"
    cd "$HOME/app"
    
    # Install dependencies
    npm install --production
    
    # Create PM2 ecosystem file
    cat > ecosystem.config.js << 'EOF'
module.exports = {
  apps: [{
    name: 'node-app',
    script: 'server.js',
    instances: 'max',
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: '/var/log/pm2/app-error.log',
    out_file: '/var/log/pm2/app-out.log',
    log_file: '/var/log/pm2/app.log',
    max_memory_restart: '1G',
    node_args: '--max_old_space_size=1024',
    watch: false,
    ignore_watch: ['node_modules', 'logs'],
    restart_delay: 4000
  }]
};
EOF
    
    # Create PM2 log directory
    sudo mkdir -p /var/log/pm2
    sudo chown $USER:$USER /var/log/pm2
    
    log_success "Application setup completed"
}

# Configure Nginx
configure_nginx() {
    log_info "Configuring Nginx..."
    
    # Create Nginx configuration
    sudo tee /etc/nginx/sites-available/default > /dev/null << EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME} www.${DOMAIN_NAME};
    
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF
    
    # Test Nginx configuration
    sudo nginx -t
    sudo systemctl restart nginx
    sudo systemctl enable nginx
    
    log_success "Nginx configured"
}

# Start application
start_application() {
    log_info "Starting application with PM2..."
    
    cd "$HOME/app"
    
    # Start application with PM2
    pm2 start ecosystem.config.js
    pm2 save
    
    # Setup PM2 startup script
    PM2_STARTUP_CMD=$(pm2 startup systemd -u $USER --hp $HOME | tail -n 1)
    eval "$PM2_STARTUP_CMD"
    
    # Wait for application to start
    sleep 30
    
    # Test application
    if curl -f http://localhost:3000 > /dev/null 2>&1; then
        log_success "Application started successfully"
    else
        log_warning "Application may not be responding on port 3000"
    fi
}

# Setup SSL certificates
setup_ssl() {
    log_info "Setting up SSL certificates..."
    
    # Obtain SSL certificate
    sudo certbot --nginx \
        -d "$DOMAIN_NAME" \
        -d "www.$DOMAIN_NAME" \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL"
    
    if [[ $? -eq 0 ]]; then
        log_success "SSL certificates obtained successfully"
    else
        error_exit "Failed to obtain SSL certificates"
    fi
}

# Setup automatic certificate renewal
setup_auto_renewal() {
    log_info "Setting up automatic certificate renewal..."
    
    # Create renewal script
    sudo tee /usr/local/bin/renew-certificates.sh > /dev/null << 'EOF'
#!/bin/bash
set -e

echo "$(date): Starting certificate renewal..." >> /var/log/certbot-renewal.log

# Renew certificates
certbot renew --quiet --nginx

if [[ $? -eq 0 ]]; then
    echo "$(date): Certificate renewal successful" >> /var/log/certbot-renewal.log
    systemctl reload nginx
else
    echo "$(date): Certificate renewal failed" >> /var/log/certbot-renewal.log
    exit 1
fi
EOF
    
    sudo chmod +x /usr/local/bin/renew-certificates.sh
    
    # Setup cron job for renewal every 2.5 months (every Sunday at 2 AM, roughly every 75 days)
    (crontab -l 2>/dev/null; echo "0 2 * * 0 /usr/local/bin/renew-certificates.sh") | crontab -
    
    log_success "Automatic certificate renewal configured"
}

# Create Cloudflare DNS update script
create_dns_update_script() {
    log_info "Creating Cloudflare DNS update script..."
    
    sudo tee /usr/local/bin/update-cloudflare-dns.sh > /dev/null << EOF
#!/bin/bash
set -e

CF_API_TOKEN="${CF_API_TOKEN}"
DOMAIN_NAME="${DOMAIN_NAME}"
SERVER_IP="\$(curl -s ifconfig.me)"

if [[ -z "\$CF_API_TOKEN" || -z "\$DOMAIN_NAME" || -z "\$SERVER_IP" ]]; then
    echo "Error: Missing required environment variables"
    echo "Required: CF_API_TOKEN, DOMAIN_NAME, SERVER_IP"
    exit 1
fi

# Get Zone ID
ZONE_ID=\$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=\${DOMAIN_NAME}" \\
    -H "Authorization: Bearer \${CF_API_TOKEN}" \\
    -H "Content-Type: application/json" | jq -r '.result[0].id')

if [[ "\$ZONE_ID" == "null" || -z "\$ZONE_ID" ]]; then
    echo "Error: Could not find zone for domain \${DOMAIN_NAME}"
    exit 1
fi

# Function to update DNS record
update_record() {
    local record_name="\$1"
    
    RECORD_ID=\$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/\${ZONE_ID}/dns_records?type=A&name=\${record_name}" \\
        -H "Authorization: Bearer \${CF_API_TOKEN}" \\
        -H "Content-Type: application/json" | jq -r '.result[0].id')
    
    if [[ "\$RECORD_ID" == "null" || -z "\$RECORD_ID" ]]; then
        # Create new A record
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/\${ZONE_ID}/dns_records" \\
            -H "Authorization: Bearer \${CF_API_TOKEN}" \\
            -H "Content-Type: application/json" \\
            --data "{\\"type\\":\\"A\\",\\"name\\":\\"\${record_name}\\",\\"content\\":\\"\${SERVER_IP}\\",\\"ttl\\":300}"
        echo "Created A record for \${record_name}"
    else
        # Update existing A record
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/\${ZONE_ID}/dns_records/\${RECORD_ID}" \\
            -H "Authorization: Bearer \${CF_API_TOKEN}" \\
            -H "Content-Type: application/json" \\
            --data "{\\"type\\":\\"A\\",\\"name\\":\\"\${record_name}\\",\\"content\\":\\"\${SERVER_IP}\\",\\"ttl\\":300}"
        echo "Updated A record for \${record_name}"
    fi
}

# Update both root and www records
update_record "\${DOMAIN_NAME}"
update_record "www.\${DOMAIN_NAME}"
EOF
    
    sudo chmod +x /usr/local/bin/update-cloudflare-dns.sh
    
    log_success "DNS update script created"
}

# Final health checks
perform_health_checks() {
    log_info "Performing final health checks..."
    
    # Check if application is running
    if pm2 list | grep -q "node-app"; then
        log_success "PM2 application is running"
    else
        log_warning "PM2 application may not be running properly"
    fi
    
    # Check Nginx status
    if sudo systemctl is-active --quiet nginx; then
        log_success "Nginx is running"
    else
        log_error "Nginx is not running"
    fi
    
    # Check HTTP response
    sleep 10
    if curl -f -s "http://$DOMAIN_NAME" > /dev/null; then
        log_success "HTTP endpoint is accessible"
    else
        log_warning "HTTP endpoint may not be accessible"
    fi
    
    # Check HTTPS response
    if curl -f -s "https://$DOMAIN_NAME" > /dev/null; then
        log_success "HTTPS endpoint is accessible"
    else
        log_warning "HTTPS endpoint may not be accessible yet (DNS propagation or SSL setup pending)"
    fi
    
    # Check certificate
    if sudo certbot certificates | grep -q "$DOMAIN_NAME"; then
        log_success "SSL certificate is installed"
    else
        log_warning "SSL certificate may not be properly installed"
    fi
}

# Print final summary
print_summary() {
    log_success "🎉 Setup completed successfully!"
    echo
    echo -e "${GREEN}📋 Summary:${NC}"
    echo -e "  🌐 Application URL: https://$DOMAIN_NAME"
    echo -e "  📊 Cloudflare Dashboard: https://dash.cloudflare.com"
    echo -e "  📁 Application Directory: $HOME/app"
    echo -e "  📝 Nginx Config: /etc/nginx/sites-available/default"
    echo
    echo -e "${BLUE}🔧 Management Commands:${NC}"
    echo -e "  PM2 Status:     ${YELLOW}pm2 status${NC}"
    echo -e "  PM2 Logs:       ${YELLOW}pm2 logs${NC}"
    echo -e "  PM2 Restart:    ${YELLOW}pm2 restart all${NC}"
    echo -e "  Nginx Status:   ${YELLOW}sudo systemctl status nginx${NC}"
    echo -e "  Nginx Restart:  ${YELLOW}sudo systemctl restart nginx${NC}"
    echo -e "  Check Certs:    ${YELLOW}sudo certbot certificates${NC}"
    echo -e "  Renew Certs:    ${YELLOW}sudo /usr/local/bin/renew-certificates.sh${NC}"
    echo -e "  Update DNS:     ${YELLOW}sudo /usr/local/bin/update-cloudflare-dns.sh${NC}"
    echo
    echo -e "${GREEN}📊 Cloudflare Analytics:${NC}"
    echo -e "  Access your Cloudflare dashboard to view:"
    echo -e "  • Traffic analytics and visitor metrics"
    echo -e "  • Geographic distribution of requests"
    echo -e "  • Response time and cache hit rates"
    echo -e "  • Security events and bot traffic"
}

# Main execution
main() {
    log_info "Starting automated Node.js + Cloudflare + HTTPS setup..."
    
    check_root
    validate_env
    update_system
    install_packages
    setup_firewall
    install_node
    update_cloudflare_dns
    # setup_application
    configure_nginx
    # start_application
    setup_ssl
    setup_auto_renewal
    create_dns_update_script
    perform_health_checks
    print_summary
    
    log_success "🚀 All done! Your application should be running at https://$DOMAIN_NAME"
}

# Execute main function
main "$@"