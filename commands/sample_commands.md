# Disable UFW first
sudo ufw disable

# Reset all existing rules
sudo ufw --force reset

# Set default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (port 22)
sudo ufw allow 22

# Allow HTTP (port 80)
sudo ufw allow 80

# Allow HTTPS (port 443)
sudo ufw allow 443

# Allow Node.js app (port 3000)
sudo ufw allow 3000

# Allow RPC (port 111) - both TCP and UDP
sudo ufw allow 111/tcp
sudo ufw allow 111/udp

# Allow DNS (port 53) - both TCP and UDP
sudo ufw allow 53/tcp
sudo ufw allow 53/udp

# Allow chronyd/NTP (port 323) - UDP
sudo ufw allow 323/udp

# Allow Python service (port 61209)
sudo ufw allow 61209

# Allow Python service (port 7000)
sudo ufw allow 7000

# Allow New Relic (port 18003)
sudo ufw allow 18003

# Allow Cloudflared (port 20241)
sudo ufw allow 20241

# Enable UFW
sudo ufw enable

# Check status
sudo ufw status numbered





##################

# Fail2Ban
# Install Fail2Ban
sudo apt update
sudo apt install fail2ban -y

# Create custom jail configuration
# Get current Cloudflare IP ranges
curl -s https://www.cloudflare.com/ips-v4 > /tmp/cf-ips-v4.txt
curl -s https://www.cloudflare.com/ips-v6 > /tmp/cf-ips-v6.txt

# Create Cloudflare whitelist
CF_IPS_V4=$(cat /tmp/cf-ips-v4.txt | tr '\n' ' ')
CF_IPS_V6=$(cat /tmp/cf-ips-v6.txt | tr '\n' ' ')

# Create jail configuration with Cloudflare whitelist
sudo tee /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 86400
findtime = 600
maxretry = 5
backend = auto

# Whitelist Cloudflare IPs
ignoreip = 127.0.0.1/8 ::1 $CF_IPS_V4 $CF_IPS_V6

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10
findtime = 600
bantime = 7200

[nginx-botsearch]
enabled = true
filter = nginx-botsearch
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 86400
EOF

# Create the custom filters
sudo tee /etc/fail2ban/filter.d/nginx-limit-req.conf << 'EOF'
[Definition]
failregex = limiting requests, excess: .* by zone .*, client: <HOST>
ignoreregex =
EOF

sudo tee /etc/fail2ban/filter.d/nginx-botsearch.conf << 'EOF'
[Definition]
failregex = <HOST>.*GET.*(\.php|\.asp|\.exe|\.pl|\.cgi|\.scgi)
ignoreregex =
EOF

# Start Fail2Ban
sudo systemctl restart fail2ban
sudo systemctl enable fail2ban

# Verify Cloudflare IPs are whitelisted
sudo fail2ban-client get sshd ignoreip