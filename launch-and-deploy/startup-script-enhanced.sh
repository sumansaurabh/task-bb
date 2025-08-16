#!/bin/bash

#############################################################################
# Google Cloud Startup Script - Complete Node.js App Deployment
# 
# This script sets up a complete production environment with:
# - Node.js via NVM  
# - Nginx reverse proxy
# - PM2 process management
# - Basic security hardening
# - Application deployment from GitHub
#############################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a /var/log/startup-script.log
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a /var/log/startup-script.log
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a /var/log/startup-script.log
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a /var/log/startup-script.log
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

log_info "Starting comprehensive Node.js deployment at $(date)"

# Environment variables with defaults
DOMAIN_NAME="${DOMAIN_NAME:-localhost}"
GITHUB_REPO="${GITHUB_REPO:-}"
APP_PORT="${APP_PORT:-3000}"
NODE_ENV="${NODE_ENV:-production}"

log_info "Configuration: DOMAIN=$DOMAIN_NAME, PORT=$APP_PORT, ENV=$NODE_ENV"

# Create nodeuser with proper setup
log_info "Setting up nodeuser account..."
if ! id -u nodeuser > /dev/null 2>&1; then
    useradd -m -s /bin/bash nodeuser
    usermod -aG sudo nodeuser
    echo "nodeuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    
    # Set up SSH access
    mkdir -p /home/nodeuser/.ssh
    cp /root/.ssh/authorized_keys /home/nodeuser/.ssh/ 2>/dev/null || true
    chown -R nodeuser:nodeuser /home/nodeuser/.ssh
    chmod 700 /home/nodeuser/.ssh
    chmod 600 /home/nodeuser/.ssh/authorized_keys 2>/dev/null || true
    
    log_success "User nodeuser created successfully"
else
    log_info "User nodeuser already exists"
fi

# Update system packages
log_info "Updating system packages..."
apt-get update || error_exit "Failed to update package list"

# Install essential packages
log_info "Installing essential packages..."
apt-get install -y \
    curl \
    wget \
    git \
    nginx \
    build-essential \
    ufw \
    fail2ban \
    htop \
    unzip \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release || error_exit "Failed to install packages"

log_success "Essential packages installed"

# Configure basic firewall
log_info "Configuring firewall..."
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 'Nginx Full'
ufw allow 80
ufw allow 443
log_success "Firewall configured"

# Install Node.js via NVM as nodeuser
log_info "Installing Node.js via NVM..."
sudo -u nodeuser bash -c '
export HOME=/home/nodeuser
cd /home/nodeuser

# Install NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

# Load NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Install and use latest LTS Node.js
nvm install --lts
nvm use --lts
nvm alias default node

# Install global packages
npm install -g pm2
npm install -g yarn

# Verify installation
node --version > /home/nodeuser/node-version.txt
npm --version > /home/nodeuser/npm-version.txt
echo "$(npm list -g --depth=0)" > /home/nodeuser/global-packages.txt
'

log_success "Node.js and global packages installed"

# Clone and setup application if GitHub repo provided
if [[ -n "$GITHUB_REPO" ]]; then
    log_info "Cloning application from $GITHUB_REPO..."
    sudo -u nodeuser bash -c "
    export HOME=/home/nodeuser
    cd /home/nodeuser
    
    # Clone repository
    git clone $GITHUB_REPO app || {
        echo 'Git clone failed, checking if directory exists...'
        if [ -d app ]; then
            cd app && git pull origin main
        fi
    }
    
    cd app
    
    # Load NVM and install dependencies
    export NVM_DIR=\"\$HOME/.nvm\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && \. \"\$NVM_DIR/nvm.sh\"
    
    # Install dependencies
    if [ -f package.json ]; then
        npm install
        echo 'Dependencies installed'
    fi
    
    # Create basic ecosystem file for PM2
    cat > ecosystem.config.js << 'EOF'
module.exports = {
  apps: [{
    name: 'app',
    script: './server.js',
    instances: 'max',
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'development',
      PORT: 3000
    },
    env_production: {
      NODE_ENV: 'production',
      PORT: 3000
    }
  }]
};
EOF
    "
    log_success "Application cloned and configured"
fi

# Configure Nginx
log_info "Configuring Nginx..."
tee /etc/nginx/sites-available/default > /dev/null << EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;
    
    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Test and reload Nginx
nginx -t || error_exit "Nginx configuration test failed"
systemctl reload nginx
systemctl enable nginx
log_success "Nginx configured and reloaded"

# Start application with PM2 if app exists
if [[ -n "$GITHUB_REPO" ]] && [[ -d "/home/nodeuser/app" ]]; then
    log_info "Starting application with PM2..."
    sudo -u nodeuser bash -c "
    export HOME=/home/nodeuser
    cd /home/nodeuser/app
    
    # Load NVM
    export NVM_DIR=\"\$HOME/.nvm\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && \. \"\$NVM_DIR/nvm.sh\"
    
    # Start with PM2
    pm2 start ecosystem.config.js --env production
    pm2 save
    pm2 startup
    "
    log_success "Application started with PM2"
fi

# Create status endpoint
log_info "Creating status files..."
sudo -u nodeuser bash -c "
echo 'Deployment completed at $(date)' > /home/nodeuser/deployment-status.txt
echo 'Server: $DOMAIN_NAME' >> /home/nodeuser/deployment-status.txt
echo 'Port: $APP_PORT' >> /home/nodeuser/deployment-status.txt
echo 'Environment: $NODE_ENV' >> /home/nodeuser/deployment-status.txt
"

# Create useful aliases for nodeuser
sudo -u nodeuser bash -c "
cat >> /home/nodeuser/.bashrc << 'EOF'

# Node.js aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'

# PM2 aliases
alias pm2l='pm2 list'
alias pm2s='pm2 status'
alias pm2r='pm2 restart all'
alias pm2stop='pm2 stop all'

# System aliases
alias logs='sudo tail -f /var/log/nginx/access.log'
alias errors='sudo tail -f /var/log/nginx/error.log'

# Load NVM automatically
export NVM_DIR=\"\$HOME/.nvm\"
[ -s \"\$NVM_DIR/nvm.sh\" ] && \. \"\$NVM_DIR/nvm.sh\"
[ -s \"\$NVM_DIR/bash_completion\" ] && \. \"\$NVM_DIR/bash_completion\"
EOF
"

log_success "User environment configured"

# Final system status
log_info "Deployment Summary:"
log_info "- Node.js: $(sudo -u nodeuser bash -c 'export NVM_DIR="/home/nodeuser/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"; node --version')"
log_info "- Nginx: $(nginx -v 2>&1)"
log_info "- PM2: $(sudo -u nodeuser bash -c 'export NVM_DIR="/home/nodeuser/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"; pm2 --version')"
log_info "- Domain: $DOMAIN_NAME"
log_info "- Application Port: $APP_PORT"

log_success "🚀 Complete Node.js deployment finished successfully at $(date)"
log_info "Access your application at: http://$DOMAIN_NAME"
