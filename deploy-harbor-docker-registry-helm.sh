#!/bin/bash

# Harbor Helm Chart Deployment Script
# This uses the official Harbor Helm chart which is much more reliable

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
    echo "🚀 =================================="
    echo "   HARBOR HELM DEPLOYMENT"
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

# Get configuration
echo ""
print_step "Harbor Configuration"

read -p "🌐 Your domain (e.g., yourdomain.com): " DOMAIN
read -p "👤 Harbor admin username (default: admin): " USERNAME
USERNAME=${USERNAME:-admin}
read -s -p "🔐 Harbor admin password: " PASSWORD
echo ""
read -p "📧 Your email: " EMAIL

if [ -z "$DOMAIN" ] || [ -z "$PASSWORD" ] || [ -z "$EMAIL" ]; then
    print_error "All fields are required"
    exit 1
fi

HARBOR_URL="harbor.$DOMAIN"

echo ""
print_step "Configuration Summary:"
echo "Harbor URL: https://$HARBOR_URL"
echo "Username: $USERNAME"
echo ""

read -p "Continue with Harbor deployment? (y/N): " confirm
if [[ $confirm != [yY] ]]; then
    echo "Deployment cancelled"
    exit 0
fi

# Add Harbor Helm repository
print_step "Adding Harbor Helm repository..."
helm repo add harbor https://helm.goharbor.io
helm repo update
print_success "Harbor Helm repo added"

# Create namespace
print_step "Creating harbor namespace..."
kubectl create namespace harbor --dry-run=client -o yaml | kubectl apply -f -

# Create values file for Harbor
print_step "Creating Harbor configuration..."

cat > harbor-values.yaml << EOF
expose:
  type: ingress
  tls:
    enabled: true
    certSource: auto
  ingress:
    hosts:
      core: $HARBOR_URL
    controller: default
    className: traefik
    annotations:
      cert-manager.io/cluster-issuer: "letsencrypt-prod"
      traefik.ingress.kubernetes.io/ssl-redirect: "true"

externalURL: https://$HARBOR_URL

harborAdminPassword: "$PASSWORD"

database:
  type: internal

redis:
  type: internal

storage:
  registry:
    type: filesystem
  chartmuseum:
    type: filesystem

trivy:
  enabled: true

chartmuseum:
  enabled: true

core:
  replicas: 1

portal:
  replicas: 1

registry:
  replicas: 1
  middleware:
    cloudFront:
      baseurl: ""
      keypairid: ""
      duration: "20m"
      ipfilteredby: "none"
    redirect:
      disable: false
    storage:
      cache:
        blobdescriptor: "inmemory"
      delete:
        enabled: true
      redirect:
        disable: false
    http:
      timeout:
        read: "300s"
        write: "300s"
        idle: "300s"
      relativeurls: false
      draintimeout: "60s"

persistence:
  enabled: true
  resourcePolicy: "keep"
  persistentVolumeClaim:
    registry:
      size: 20Gi
    chartmuseum:
      size: 5Gi
    database:
      size: 5Gi
    redis:
      size: 1Gi
    trivy:
      size: 5Gi
EOF

print_success "Harbor configuration created"

# Deploy Harbor
print_step "Deploying Harbor with Helm..."
helm upgrade --install harbor harbor/harbor \
  --namespace harbor \
  --values harbor-values.yaml \
  --wait \
  --timeout=10m

print_success "Harbor deployed successfully"

# Create ImagePullSecret
print_step "Creating Kubernetes ImagePullSecret..."

kubectl delete secret harbor-registry-secret -n default 2>/dev/null || true

kubectl create secret docker-registry harbor-registry-secret \
    --docker-server="$HARBOR_URL" \
    --docker-username="$USERNAME" \
    --docker-password="$PASSWORD" \
    --docker-email="$EMAIL" \
    --namespace=default

print_success "ImagePullSecret created"

# Update application deployment
print_step "Updating application deployment configuration..."

if [ -f "k8s-manifests/app/deployment-private-registry.yaml" ]; then
    cp k8s-manifests/app/deployment-private-registry.yaml k8s-manifests/app/deployment-private-registry.yaml.backup
    sed -i.tmp "s|image: .*|image: $HARBOR_URL/library/backend:latest|g" k8s-manifests/app/deployment-private-registry.yaml
    sed -i.tmp "s/blackbox-registry-secret/harbor-registry-secret/g" k8s-manifests/app/deployment-private-registry.yaml
    rm k8s-manifests/app/deployment-private-registry.yaml.tmp
    print_success "Application deployment updated"
fi

# Display results
echo ""
echo -e "${GREEN}🎉 HARBOR DEPLOYMENT COMPLETE! 🎉${NC}"
echo "======================================="
echo ""
echo "🏢 Harbor Information:"
echo "  Harbor URL:   https://$HARBOR_URL"
echo "  Username:     $USERNAME"
echo "  Password:     [hidden]"
echo ""
echo "🔧 GitHub Secrets to add:"
echo "  BLACKBOX_REGISTRY_URL=$HARBOR_URL"
echo "  BLACKBOX_REGISTRY_USERNAME=$USERNAME"
echo "  BLACKBOX_REGISTRY_PASSWORD=$PASSWORD"
echo ""
echo "🎯 Next Steps:"
echo "  1. Wait for DNS to propagate: $HARBOR_URL"
echo "  2. Open https://$HARBOR_URL in browser"
echo "  3. Login with credentials above"
echo "  4. Create a project called 'library' (or use default)"
echo "  5. Add GitHub secrets for CI/CD"
echo ""
echo "🧪 Test your Harbor registry:"
echo "  docker login $HARBOR_URL"
echo "  docker tag hello-world:latest $HARBOR_URL/library/hello-world:latest"
echo "  docker push $HARBOR_URL/library/hello-world:latest"
echo ""
echo "📱 Deploy your application:"
echo "  kubectl apply -f k8s-manifests/app/deployment-private-registry.yaml"
echo ""
print_success "Harbor setup completed successfully!"
