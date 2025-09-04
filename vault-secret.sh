#!/bin/bash

# Bank-Vaults (Banzai Cloud) Deployment Script for K3s
# Secure deployment without hardcoded secrets

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_header() {
    echo -e "${PURPLE}"
    echo "🔐 =================================="
    echo "   BANK-VAULTS DEPLOYMENT"
    echo "   =================================="
    echo -e "${NC}"
}

print_step() {
    echo -e "${BLUE}📋 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_header

# Check prerequisites
print_step "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    print_error "Helm is not installed. Please install Helm first."
    echo "Install with: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    exit 1
fi

print_success "Prerequisites checked"

# Configuration
echo ""
print_step "Vault Configuration"

read -p "🌐 Your domain for Vault UI (e.g., vault.yourdomain.com): " VAULT_DOMAIN
read -p "📧 Your email for certificates: " EMAIL

if [ -z "$VAULT_DOMAIN" ] || [ -z "$EMAIL" ]; then
    print_error "Domain and email are required"
    exit 1
fi

echo ""
print_step "Configuration Summary:"
echo "Vault URL: https://$VAULT_DOMAIN"
echo "Auto-unsealing: Enabled"
echo "Secrets: Will be added securely after deployment"
echo ""

read -p "Continue with Bank-Vaults deployment? (y/N): " confirm
if [[ $confirm != [yY] ]]; then
    echo "Deployment cancelled"
    exit 0
fi

# Add Banzai Cloud Helm repository
print_step "Adding Banzai Cloud Helm repository..."
helm repo add banzaicloud-stable https://kubernetes-charts.banzaicloud.com
helm repo update
print_success "Banzai Cloud Helm repo added"

# Create namespaces
print_step "Creating namespaces..."
kubectl create namespace vault-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -

# Install Vault Operator
print_step "Installing Vault Operator..."
helm upgrade --install vault-operator banzaicloud-stable/vault-operator \
  --namespace vault-system \
  --wait \
  --timeout=5m

print_success "Vault Operator installed"

# Create Bank-Vaults configuration (WITHOUT secrets)
print_step "Creating Bank-Vaults configuration..."

cat > vault-instance.yaml << EOF
apiVersion: "vault.banzaicloud.com/v1alpha1"
kind: "Vault"
metadata:
  name: "vault"
  namespace: "vault"
spec:
  size: 1
  image: vault:1.15.2
  bankVaultsImage: banzaicloud/bank-vaults:latest
  
  # Automatic initialization and unsealing
  unsealConfig:
    kubernetes:
      secretNamespace: vault
  
  # Vault configuration
  config:
    storage:
      file:
        path: "/vault/file"
    listener:
      tcp:
        address: "0.0.0.0:8200"
        tls_disable: true
    ui: true
    api_addr: "http://vault:8200"
    cluster_addr: "http://vault:8201"
  
  # Ingress configuration
  ingress:
    enabled: true
    annotations:
      kubernetes.io/ingress.class: "traefik"
      cert-manager.io/cluster-issuer: "letsencrypt-prod"
      traefik.ingress.kubernetes.io/ssl-redirect: "true"
    spec:
      ingressClassName: traefik
      rules:
      - host: $VAULT_DOMAIN
        http:
          paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: vault
                port:
                  number: 8200
      tls:
      - hosts:
        - $VAULT_DOMAIN
        secretName: vault-tls
  
  # Service configuration
  serviceType: ClusterIP
  
  # Resources
  resources:
    vault:
      requests:
        memory: "256Mi"
        cpu: "250m"
      limits:
        memory: "512Mi"
        cpu: "500m"
  
  # Persistent storage
  volumeClaimTemplates:
    - metadata:
        name: vault-file
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
  
  # External configuration (NO SECRETS HERE)
  externalConfig:
    policies:
      - name: app-policy
        rules: |
          path "secret/data/*" {
            capabilities = ["read"]
          }
          path "secret/metadata/*" {
            capabilities = ["list"]
          }
    
    auth:
      - type: kubernetes
        roles:
          - name: app-role
            bound_service_account_names: ["default", "vault"]
            bound_service_account_namespaces: ["default", "vault", "harbor"]
            policies: ["app-policy"]
            ttl: 1h
    
    secrets:
      - path: secret
        type: kv
        description: Application secrets
        options:
          version: 2
    
    # NO startupSecrets - secrets will be added manually after deployment
EOF

print_success "Bank-Vaults configuration created (without secrets)"

# Deploy Vault instance
print_step "Deploying Vault instance..."
kubectl apply -f vault-instance.yaml

print_success "Vault instance deployed"

# Wait for Vault to be ready
print_step "Waiting for Vault to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=600s

print_success "Vault is ready"

# Get Vault root token
print_step "Retrieving Vault root token..."
sleep 30

ROOT_TOKEN=""
for i in {1..30}; do
    ROOT_TOKEN=$(kubectl get secret vault-unseal-keys -n vault -o jsonpath='{.data.vault-root}' 2>/dev/null | base64 -d 2>/dev/null || true)
    if [ ! -z "$ROOT_TOKEN" ]; then
        break
    fi
    echo "Waiting for root token... ($i/30)"
    sleep 10
done

if [ -z "$ROOT_TOKEN" ]; then
    print_warning "Could not retrieve root token automatically. Check 'kubectl get secrets -n vault'"
    ROOT_TOKEN="[Check vault-unseal-keys secret]"
else
    print_success "Root token retrieved"
fi

# Create secure secret setup script
print_step "Creating secure secret setup script..."

cat > setup-secrets.sh << 'EOF'
#!/bin/bash

# Secure Secret Setup for Bank-Vaults
set -e

VAULT_POD=$(kubectl get pods -n vault -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')

if [ -z "$VAULT_POD" ]; then
    echo "❌ Could not find Vault pod"
    exit 1
fi

echo "🔐 Setting up secrets securely..."
echo "Note: Passwords will not be shown on screen"
echo ""

# Harbor secrets
echo "📦 Harbor Configuration:"
read -p "Harbor admin username [admin]: " HARBOR_USER
HARBOR_USER=${HARBOR_USER:-admin}
read -s -p "Harbor admin password: " HARBOR_PASS
echo ""
read -s -p "Harbor registry password: " HARBOR_REG_PASS
echo ""

kubectl exec -n vault $VAULT_POD -- vault kv put secret/harbor \
    admin_username="$HARBOR_USER" \
    admin_password="$HARBOR_PASS" \
    registry_password="$HARBOR_REG_PASS" \
    url="https://harbor.bareflux.co"

echo "✅ Harbor secrets stored"

# Database secrets
echo ""
echo "🗄️  Database Configuration:"
read -p "Database username: " DB_USER
read -s -p "Database password: " DB_PASS
echo ""
read -p "Database host [postgres]: " DB_HOST
DB_HOST=${DB_HOST:-postgres}
read -p "Database name [registry]: " DB_NAME
DB_NAME=${DB_NAME:-registry}

kubectl exec -n vault $VAULT_POD -- vault kv put secret/database \
    username="$DB_USER" \
    password="$DB_PASS" \
    host="$DB_HOST" \
    database="$DB_NAME" \
    connection_string="postgresql://$DB_USER:$DB_PASS@$DB_HOST:5432/$DB_NAME"

echo "✅ Database secrets stored"

# Redis secrets
echo ""
echo "🔴 Redis Configuration:"
read -p "Redis URL [redis://harbor-redis:6379/0]: " REDIS_URL
REDIS_URL=${REDIS_URL:-redis://harbor-redis:6379/0}
read -s -p "Redis password (leave empty if none): " REDIS_PASS
echo ""

kubectl exec -n vault $VAULT_POD -- vault kv put secret/redis \
    url="$REDIS_URL" \
    password="$REDIS_PASS"

echo "✅ Redis secrets stored"

# Application secrets
echo ""
echo "🚀 Application Configuration:"
read -s -p "JWT secret (leave empty to generate): " JWT_SECRET
echo ""
if [ -z "$JWT_SECRET" ]; then
    JWT_SECRET=$(openssl rand -hex 32)
    echo "📝 Generated JWT secret"
fi

read -s -p "API key: " API_KEY
echo ""
read -p "Environment [production]: " APP_ENV
APP_ENV=${APP_ENV:-production}

kubectl exec -n vault $VAULT_POD -- vault kv put secret/app \
    jwt_secret="$JWT_SECRET" \
    api_key="$API_KEY" \
    environment="$APP_ENV"

echo "✅ Application secrets stored"
echo ""
echo "🎉 All secrets configured securely!"

# Clear sensitive variables
unset HARBOR_USER HARBOR_PASS HARBOR_REG_PASS
unset DB_USER DB_PASS DB_HOST DB_NAME
unset REDIS_URL REDIS_PASS
unset JWT_SECRET API_KEY APP_ENV

echo "🔍 Verify secrets with: ./vault-helper.sh list"
EOF

chmod +x setup-secrets.sh
print_success "Secure secret setup script created: setup-secrets.sh"

# Create helper script for secret management
print_step "Creating helper scripts..."

cat > vault-helper.sh << 'EOF'
#!/bin/bash

# Bank-Vaults Helper Script
VAULT_POD=$(kubectl get pods -n vault -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')

if [ -z "$VAULT_POD" ]; then
    echo "❌ Could not find Vault pod"
    exit 1
fi

case "$1" in
    "read"|"get")
        if [ -z "$2" ]; then
            echo "Usage: $0 read <secret-path>"
            echo "Example: $0 read secret/harbor"
            exit 1
        fi
        kubectl exec -n vault $VAULT_POD -- vault kv get -format=json $2
        ;;
    "write"|"put")
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 write <secret-path> <key=value> [key=value...]"
            echo "Example: $0 write secret/harbor admin_password=newpass"
            exit 1
        fi
        kubectl exec -n vault $VAULT_POD -- vault kv put $2 ${@:3}
        ;;
    "list"|"ls")
        if [ -z "$2" ]; then
            kubectl exec -n vault $VAULT_POD -- vault kv list secret/
        else
            kubectl exec -n vault $VAULT_POD -- vault kv list $2
        fi
        ;;
    "delete"|"rm")
        if [ -z "$2" ]; then
            echo "Usage: $0 delete <secret-path>"
            exit 1
        fi
        kubectl exec -n vault $VAULT_POD -- vault kv delete $2
        ;;
    "status")
        kubectl exec -n vault $VAULT_POD -- vault status
        ;;
    "token")
        ROOT_TOKEN=$(kubectl get secret vault-unseal-keys -n vault -o jsonpath='{.data.vault-root}' | base64 -d 2>/dev/null || echo "")
        if [ ! -z "$ROOT_TOKEN" ]; then
            echo "Root token: $ROOT_TOKEN"
        else
            echo "❌ Could not retrieve root token"
        fi
        ;;
    *)
        echo "Usage: $0 {read|write|list|delete|status|token}"
        echo ""
        echo "Commands:"
        echo "  read <path>              - Read a secret"
        echo "  write <path> <key=val>   - Write a secret"
        echo "  list [path]              - List secrets"
        echo "  delete <path>            - Delete a secret"
        echo "  status                   - Show Vault status"
        echo "  token                    - Show root token"
        echo ""
        echo "Examples:"
        echo "  $0 read secret/harbor"
        echo "  $0 write secret/harbor admin_password=newpass"
        echo "  $0 list secret/"
        ;;
esac
EOF

chmod +x vault-helper.sh
print_success "Helper script created: vault-helper.sh"

# Create cleanup script
cat > vault-cleanup.sh << 'EOF'
#!/bin/bash
echo "🧹 Cleaning up Bank-Vaults deployment..."
kubectl delete vault vault -n vault 2>/dev/null || true
kubectl delete namespace vault 2>/dev/null || true
helm uninstall vault-operator -n vault-system 2>/dev/null || true
kubectl delete namespace vault-system 2>/dev/null || true
rm -f vault-instance.yaml setup-secrets.sh vault-helper.sh vault-info.txt
echo "✅ Bank-Vaults cleanup complete!"
EOF
chmod +x vault-cleanup.sh

# Display results
echo ""
echo -e "${GREEN}🎉 BANK-VAULTS DEPLOYMENT COMPLETE! 🎉${NC}"
echo "======================================="
echo ""
echo "🔐 Vault Information:"
echo "  Vault URL:     https://$VAULT_DOMAIN"
echo "  Root Token:    $ROOT_TOKEN"
echo "  Namespace:     vault"
echo "  Auto-unsealing: ✅ Enabled"
echo ""
echo "🔒 NEXT STEP - Add Your Secrets:"
echo "  Run: ./setup-secrets.sh"
echo "  This will prompt for your actual secrets securely"
echo ""
echo "🛠️  Management Commands:"
echo "  ./vault-helper.sh list          - List all secrets"
echo "  ./vault-helper.sh read secret/harbor"
echo "  ./vault-helper.sh write secret/app key=value"
echo "  ./vault-helper.sh status        - Check Vault status"
echo ""
echo "🌐 Access Vault UI:"
echo "  URL: https://$VAULT_DOMAIN"
echo "  Token: $ROOT_TOKEN"
echo ""
echo "🔧 Complete Setup:"
echo "  1. Run ./setup-secrets.sh to add your secrets"
echo "  2. Wait for DNS: $VAULT_DOMAIN"
echo "  3. Test: ./vault-helper.sh list"
echo "  4. Configure apps to use Vault"
echo ""

# Save important info to file
cat > vault-info.txt << EOF
Bank-Vaults Deployment Information
==================================

Vault URL: https://$VAULT_DOMAIN
Root Token: $ROOT_TOKEN
Namespace: vault

Security Features:
- Automatic initialization ✅
- Automatic unsealing ✅  
- Kubernetes authentication ✅
- No secrets in configuration ✅
- Ingress with TLS ✅

Setup Scripts:
- ./setup-secrets.sh     - Add secrets securely
- ./vault-helper.sh      - Manage secrets
- ./vault-cleanup.sh     - Remove everything

Next: Run ./setup-secrets.sh to add your actual secrets
EOF

print_success "Bank-Vaults setup completed!"
print_success "Info saved to vault-info.txt"
print_warning "IMPORTANT: Run ./setup-secrets.sh to add your secrets"