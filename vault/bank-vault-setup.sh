#!/bin/bash

# Bank-Vaults (bank-vaults.dev) Deployment Script for K3s
# Fixed version with proper RBAC and configuration
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
    echo "   BANK-VAULTS DEPLOYMENT (FIXED)"
    echo "   (Updated for bank-vaults.dev)"
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
echo "Auto-unsealing: Enabled (Kubernetes secrets)"
echo "Storage Backend: File (for dev) / Raft (for production)"
echo "Secrets: Will be added securely after deployment"
echo ""

read -p "Deploy production-ready HA cluster with Raft? (y/N): " HA_MODE
HA_MODE=${HA_MODE:-n}

read -p "Continue with Bank-Vaults deployment? (y/N): " confirm
if [[ $confirm != [yY] ]]; then
    echo "Deployment cancelled"
    exit 0
fi

# Add Helm repositories
print_step "Adding Helm repositories..."
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager if not present
print_step "Checking/Installing cert-manager..."
if ! kubectl get namespace cert-manager &> /dev/null; then
    kubectl create namespace cert-manager
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version v1.13.0 \
        --set installCRDs=true \
        --wait
    
    # Wait for cert-manager to be ready
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
    print_success "cert-manager installed"
else
    print_success "cert-manager already installed"
fi

# Create ClusterIssuer for Let's Encrypt
print_step "Creating Let's Encrypt ClusterIssuer..."
cat > letsencrypt-issuer.yaml << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $EMAIL
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: traefik
EOF

kubectl apply -f letsencrypt-issuer.yaml
print_success "Let's Encrypt ClusterIssuer created"

# Install Vault Operator using new OCI registry
print_step "Installing Vault Operator from OCI registry..."
helm upgrade --install vault-operator \
  oci://ghcr.io/bank-vaults/helm-charts/vault-operator \
  --timeout=5m \
  --wait

print_success "Vault Operator installed"

# Create ServiceAccount and RBAC
print_step "Creating ServiceAccount and RBAC resources..."
cat > vault-rbac.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: vault-secrets
  namespace: default
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: vault-secrets
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: vault-secrets
subjects:
- kind: ServiceAccount
  name: vault
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: vault-auth
rules:
- apiGroups: [""]
  resources: ["serviceaccounts", "serviceaccounts/token"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-auth
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: vault-auth
subjects:
- kind: ServiceAccount
  name: vault
  namespace: default
EOF

kubectl apply -f vault-rbac.yaml
print_success "ServiceAccount and RBAC resources created"

# Choose deployment mode
if [[ $HA_MODE == [yY] ]]; then
    print_step "Creating production HA Vault configuration with Raft..."
    VAULT_SIZE=3
    STORAGE_TYPE="raft"
else
    print_step "Creating single-node Vault configuration..."
    VAULT_SIZE=1
    STORAGE_TYPE="file"
fi

# Create Bank-Vaults configuration (WITHOUT secrets)
print_step "Creating Bank-Vaults Vault CR..."

if [[ $HA_MODE == [yY] ]]; then
# HA Raft Configuration
cat > vault-instance.yaml << EOF
apiVersion: "vault.banzaicloud.com/v1alpha1"
kind: "Vault"
metadata:
  name: "vault"
  namespace: default
spec:
  size: ${VAULT_SIZE}
  image: hashicorp/vault:1.17.2
  bankVaultsImage: ghcr.io/bank-vaults/bank-vaults:v1.31.3

  tls:
    disabled: true
  
  # Service Account
  serviceAccount: vault
  serviceType: ClusterIP
  
  # Automatic initialization and unsealing
  unsealConfig:
    options:
      preFlightChecks: true
      storeRootToken: true
      secretShares: 5
      secretThreshold: 3
    kubernetes:
      secretNamespace: default
  
  # Vault configuration with Raft
  config:
    storage:
      raft:
        path: "/vault/file"
        node_id: "\${.Env.POD_NAME}"
    listener:
      tcp:
        address: "0.0.0.0:8200"
        tls_cert_file: /vault/tls/server.crt
        tls_key_file: /vault/tls/server.key
    api_addr: "https://\${.Env.POD_NAME}.vault-internal:8200"
    cluster_addr: "https://\${.Env.POD_NAME}.vault-internal:8201"
    ui: true
  
  # Ingress configuration
  ingress:
    annotations:
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
  
  # Resources
  resources:
    vault:
      requests:
        memory: "512Mi"
        cpu: "250m"
      limits:
        memory: "1Gi"
        cpu: "500m"
  
  # Persistent storage for Raft
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
            capabilities = ["create", "read", "update", "delete", "list"]
          }
          path "secret/metadata/*" {
            capabilities = ["list"]
          }
    
    auth:
      - type: kubernetes
        roles:
          - name: default
            bound_service_account_names: ["default", "vault", "vault-secrets-webhook"]
            bound_service_account_namespaces: ["default", "vault-infra"]
            policies: ["app-policy"]
            ttl: 1h
    
    secrets:
      - path: secret
        type: kv
        description: Application secrets
        options:
          version: 2
EOF
else
# Single-node file storage Configuration  
cat > vault-instance.yaml << EOF
apiVersion: "vault.banzaicloud.com/v1alpha1"
kind: "Vault"
metadata:
  name: "vault"
  namespace: default
spec:
  size: 1
  image: hashicorp/vault:1.17.2
  bankVaultsImage: ghcr.io/bank-vaults/bank-vaults:v1.31.3

  

  
  # Service Account
  serviceAccount: vault
  serviceType: ClusterIP
  
  # Automatic initialization and unsealing
  unsealConfig:
    options:
      preFlightChecks: true
      storeRootToken: true
      secretShares: 5
      secretThreshold: 3
    kubernetes:
      secretNamespace: default
  
  # Vault configuration with File storage
  config:
    storage:
      file:
        path: "/vault/file"
    listener:
      tcp:
        address: "0.0.0.0:8200"
        tls_disable: true
    ui: true
    api_addr: "https://vault.default:8200"
  
  # Ingress configuration
  ingress:
    annotations:
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
            capabilities = ["create", "read", "update", "delete", "list"]
          }
          path "secret/metadata/*" {
            capabilities = ["list"]
          }
    
    auth:
      - type: kubernetes
        roles:
          - name: default
            bound_service_account_names: ["default", "vault", "vault-secrets-webhook"]
            bound_service_account_namespaces: ["default", "vault-infra"]
            policies: ["app-policy"]
            ttl: 1h
    
    secrets:
      - path: secret
        type: kv
        description: Application secrets
        options:
          version: 2
EOF
fi

print_success "Bank-Vaults Vault CR created (without secrets)"

# Deploy Vault instance
print_step "Deploying Vault instance..."
kubectl apply -f vault-instance.yaml

print_success "Vault instance deployed"

# Wait for Vault to be ready with better error handling
print_step "Waiting for Vault to be ready..."
echo "This may take several minutes for the first initialization..."

# Wait for vault pods to be created
timeout=300
elapsed=0
while [ $elapsed -lt $timeout ]; do
    vault_pods=$(kubectl get pods -l app.kubernetes.io/name=vault --no-headers 2>/dev/null | wc -l)
    if [ $vault_pods -gt 0 ]; then
        break
    fi
    echo "Waiting for Vault pods to be created... ($elapsed/$timeout seconds)"
    sleep 10
    elapsed=$((elapsed + 10))
done

if [ $vault_pods -eq 0 ]; then
    print_error "Vault pods were not created within $timeout seconds"
    print_error "Check the logs with: kubectl describe vault vault"
    exit 1
fi

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault --timeout=600s

print_success "Vault is ready"

# Create vault-infra namespace if it doesn't exist
print_step "Creating vault-infra namespace..."
kubectl create namespace vault-infra --dry-run=client -o yaml | kubectl apply -f -

# Install Vault Secrets Webhook
print_step "Installing Vault Secrets Webhook..."
helm upgrade --install vault-secrets-webhook \
  oci://ghcr.io/bank-vaults/helm-charts/vault-secrets-webhook \
  --namespace vault-infra \
  --wait

print_success "Vault Secrets Webhook installed"

# Get Vault root token with better error handling
print_step "Retrieving Vault root token..."
sleep 30

ROOT_TOKEN=""
for i in {1..30}; do
    ROOT_TOKEN=$(kubectl get secret vault-unseal-keys -o jsonpath='{.data.vault-root}' 2>/dev/null | base64 -d 2>/dev/null || true)
    if [ ! -z "$ROOT_TOKEN" ]; then
        break
    fi
    echo "Waiting for root token... ($i/30)"
    sleep 10
done

if [ -z "$ROOT_TOKEN" ]; then
    print_warning "Could not retrieve root token automatically."
    print_warning "Check manually with: kubectl get secrets vault-unseal-keys -o jsonpath='{.data.vault-root}' | base64 -d"
    ROOT_TOKEN="[Check vault-unseal-keys secret]"
else
    print_success "Root token retrieved"
fi

# Create secure secret setup script (same as before)
print_step "Creating secure secret setup script..."

cat > setup-secrets.sh << 'EOF'
#!/bin/bash

# Secure Secret Setup for HashiCorp Vault via Bank-Vaults
set -e

VAULT_POD=$(kubectl get pods -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')

if [ -z "$VAULT_POD" ]; then
    echo "❌ Could not find Vault pod"
    exit 1
fi

# Get root token
export VAULT_TOKEN=$(kubectl get secret vault-unseal-keys -o jsonpath='{.data.vault-root}' | base64 -d)

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

kubectl exec $VAULT_POD -- env VAULT_TOKEN="$VAULT_TOKEN" vault kv put secret/harbor \
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

kubectl exec $VAULT_POD -- env VAULT_TOKEN="$VAULT_TOKEN" vault kv put secret/database \
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

kubectl exec $VAULT_POD -- env VAULT_TOKEN="$VAULT_TOKEN" vault kv put secret/redis \
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

kubectl exec $VAULT_POD -- env VAULT_TOKEN="$VAULT_TOKEN" vault kv put secret/app \
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
unset VAULT_TOKEN

echo "🔍 Verify secrets with: ./vault-helper.sh list"
EOF

chmod +x setup-secrets.sh
print_success "Secure secret setup script created: setup-secrets.sh"

# Create helper script for secret management (same as before but with better error handling)
print_step "Creating helper scripts..."

cat > vault-helper.sh << 'EOF'
#!/bin/bash

# Bank-Vaults Helper Script
VAULT_POD=$(kubectl get pods -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')

if [ -z "$VAULT_POD" ]; then
    echo "❌ Could not find Vault pod"
    exit 1
fi

# Get root token
export VAULT_TOKEN=$(kubectl get secret vault-unseal-keys -o jsonpath='{.data.vault-root}' | base64 -d 2>/dev/null)

if [ -z "$VAULT_TOKEN" ]; then
    echo "❌ Could not retrieve Vault token"
    exit 1
fi

case "$1" in
    "read"|"get")
        if [ -z "$2" ]; then
            echo "Usage: $0 read <secret-path>"
            echo "Example: $0 read secret/harbor"
            exit 1
        fi
        kubectl exec $VAULT_POD -- env VAULT_TOKEN="$VAULT_TOKEN" vault kv get -format=json $2
        ;;
    "write"|"put")
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 write <secret-path> <key=value> [key=value...]"
            echo "Example: $0 write secret/harbor admin_password=newpass"
            exit 1
        fi
        kubectl exec $VAULT_POD -- env VAULT_TOKEN="$VAULT_TOKEN" vault kv put $2 ${@:3}
        ;;
    "list"|"ls")
        if [ -z "$2" ]; then
            kubectl exec $VAULT_POD -- env VAULT_TOKEN="$VAULT_TOKEN" vault kv list secret/
        else
            kubectl exec $VAULT_POD -- env VAULT_TOKEN="$VAULT_TOKEN" vault kv list $2
        fi
        ;;
    "delete"|"rm")
        if [ -z "$2" ]; then
            echo "Usage: $0 delete <secret-path>"
            exit 1
        fi
        kubectl exec $VAULT_POD -- env VAULT_TOKEN="$VAULT_TOKEN" vault kv delete $2
        ;;
    "status")
        kubectl exec $VAULT_POD -- env VAULT_TOKEN="$VAULT_TOKEN" vault status
        ;;
    "token")
        ROOT_TOKEN=$(kubectl get secret vault-unseal-keys -o jsonpath='{.data.vault-root}' | base64 -d 2>/dev/null || echo "")
        if [ ! -z "$ROOT_TOKEN" ]; then
            echo "Root token: $ROOT_TOKEN"
        else
            echo "❌ Could not retrieve root token"
        fi
        ;;
    "logs")
        kubectl logs $VAULT_POD
        ;;
    "describe")
        kubectl describe vault vault
        ;;
    *)
        echo "Usage: $0 {read|write|list|delete|status|token|logs|describe}"
        echo ""
        echo "Commands:"
        echo "  read <path>              - Read a secret"
        echo "  write <path> <key=val>   - Write a secret"
        echo "  list [path]              - List secrets"
        echo "  delete <path>            - Delete a secret"
        echo "  status                   - Show Vault status"
        echo "  token                    - Show root token"
        echo "  logs                     - Show vault pod logs"
        echo "  describe                 - Describe vault resource"
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

# Clean up temporary files
rm -f letsencrypt-issuer.yaml vault-rbac.yaml

# Display results
echo ""
echo -e "${GREEN}🎉 BANK-VAULTS DEPLOYMENT COMPLETE! 🎉${NC}"
echo "======================================="
echo ""
echo "🔐 Vault Information:"
echo "  Vault URL:     https://$VAULT_DOMAIN"
echo "  Root Token:    $ROOT_TOKEN"
echo "  Storage:       $STORAGE_TYPE"
echo "  Instances:     $VAULT_SIZE"
echo "  Auto-unsealing: ✅ Enabled"
echo "  Auto-init: ✅ Enabled"
echo "  Webhook: ✅ Installed"
echo "  Cert-manager: ✅ Configured"
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
echo "  ./vault-helper.sh logs          - Check Vault logs"
echo ""
echo "🌐 Access Vault UI:"
echo "  URL: https://$VAULT_DOMAIN"
echo "  Token: $ROOT_TOKEN"
echo ""
echo "🔧 Troubleshooting:"
echo "  ./vault-helper.sh logs          - Check logs"
echo "  ./vault-helper.sh describe      - Check resource status"
echo "  kubectl get vault vault -o yaml - Full resource status"
echo ""

# Save important info to file
cat > vault-info.txt << EOF
Bank-Vaults Deployment Information
==================================

Vault URL: https://$VAULT_DOMAIN
Root Token: $ROOT_TOKEN
Storage Backend: $STORAGE_TYPE
Instances: $VAULT_SIZE

Security Features:
- Bank-Vaults operator ✅
- Automatic initialization ✅
- Automatic unsealing ✅  
- Kubernetes authentication ✅
- Vault Secrets Webhook ✅
- Cert-manager with Let's Encrypt ✅
- No secrets in configuration ✅
- Ingress with TLS ✅

Setup Scripts:
- ./setup-secrets.sh     - Add secrets securely
- ./vault-helper.sh      - Manage secrets

Next: Run ./setup-secrets.sh to add your actual secrets

Latest Versions:
- Bank-Vaults: v1.31.3 (September 2025)
- Vault Operator: v1.21.0  
- All releases now use 'v' prefix

Repository: Bank-Vaults now at bank-vaults.dev
Charts: oci://ghcr.io/bank-vaults/helm-charts/
GitHub: https://github.com/bank-vaults/bank-vaults
EOF

print_success "Bank-Vaults setup completed!"
print_success "Info saved to vault-info.txt"
print_warning "IMPORTANT: Run ./setup-secrets.sh to add your secrets"