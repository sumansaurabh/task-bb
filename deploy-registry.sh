#!/bin/bash

# Harbor Registry Quick Setup Script
# This script helps you deploy Harbor - Enterprise Docker Registry with UI

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${PURPLE}"
    echo "🚀 =================================="
    echo "   HARBOR REGISTRY SETUP"
    echo "   =================================="
    echo -e "${NC}"
}

print_step() {
    echo -e "${BLUE}📋 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
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

print_success "Prerequisites checked"

# Get configuration
echo ""
print_step "Harbor Configuration"
echo ""

read -p "🌐 Your domain (e.g., yourdomain.com): " DOMAIN
read -p "👤 Harbor admin username (default: admin): " USERNAME
USERNAME=${USERNAME:-admin}
read -s -p "🔐 New Harbor admin password (leave empty to use Harbor12345): " PASSWORD
echo ""
PASSWORD=${PASSWORD:-Harbor12345}
read -p "📧 Your email: " EMAIL

# Validate inputs
if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    print_error "Domain and email are required"
    exit 1
fi

HARBOR_URL="harbor.$DOMAIN"

echo ""
print_step "Configuration Summary:"
echo "Harbor URL: https://$HARBOR_URL"
echo "Username: $USERNAME"
echo "Password: [hidden]"
echo ""

read -p "Continue with Harbor deployment? (y/N): " confirm
if [[ $confirm != [yY] ]]; then
    echo "Deployment cancelled"
    exit 0
fi

# Update harbor-registry.yaml with domain
print_step "Updating Harbor configuration..."

# Create backup
cp k8s-manifests/blackbox-registry/harbor-registry.yaml k8s-manifests/blackbox-registry/harbor-registry.yaml.backup

# Update domain in harbor-registry.yaml
sed -i.tmp "s/harbor\.bareflux\.com/$HARBOR_URL/g" k8s-manifests/blackbox-registry/harbor-registry.yaml

# Update admin password if changed
if [ "$PASSWORD" != "Harbor12345" ]; then
    PASSWORD_BASE64=$(echo -n "$PASSWORD" | base64)
    sed -i.tmp "s/password: .*/password: $PASSWORD_BASE64/" k8s-manifests/blackbox-registry/harbor-registry.yaml
fi

# Clean up temp files
rm k8s-manifests/blackbox-registry/harbor-registry.yaml.tmp

print_success "Configuration updated"

# Deploy Harbor
print_step "Deploying Harbor to Kubernetes..."

kubectl apply -f k8s-manifests/blackbox-registry/harbor-registry.yaml

print_success "Harbor deployed"

# Wait for pods
print_step "Waiting for Harbor components to be ready (this may take 5-10 minutes)..."

# Wait for namespace to be created first
kubectl wait --for=condition=ready --timeout=30s namespace/harbor 2>/dev/null || true

# Wait for each component
print_step "Waiting for database..."
kubectl wait --for=condition=ready pod -l app=harbor-database -n harbor --timeout=300s

print_step "Waiting for Redis..."
kubectl wait --for=condition=ready pod -l app=harbor-redis -n harbor --timeout=300s

print_step "Waiting for Harbor core..."
kubectl wait --for=condition=ready pod -l app=harbor-core -n harbor --timeout=300s

print_step "Waiting for Harbor registry..."
kubectl wait --for=condition=ready pod -l app=harbor-registry -n harbor --timeout=300s

print_step "Waiting for Harbor portal..."
kubectl wait --for=condition=ready pod -l app=harbor-portal -n harbor --timeout=300s

print_success "All Harbor components are ready"

# Update deployment-private-registry.yaml
print_step "Updating application deployment configuration..."

cp k8s-manifests/app/deployment-private-registry.yaml k8s-manifests/app/deployment-private-registry.yaml.backup
sed -i.tmp "s/registry\.blackbox\.yourdomain\.com/$HARBOR_URL/g" k8s-manifests/app/deployment-private-registry.yaml
sed -i.tmp "s/blackbox-registry-secret/harbor-registry-secret/g" k8s-manifests/app/deployment-private-registry.yaml
rm k8s-manifests/app/deployment-private-registry.yaml.tmp

print_success "Application deployment updated"

# Create ImagePullSecret
print_step "Creating Kubernetes ImagePullSecret..."

# Delete existing secret if it exists
kubectl delete secret harbor-registry-secret -n default 2>/dev/null || true

kubectl create secret docker-registry harbor-registry-secret \
    --docker-server="$HARBOR_URL" \
    --docker-username="$USERNAME" \
    --docker-password="$PASSWORD" \
    --docker-email="$EMAIL" \
    --namespace=default

print_success "ImagePullSecret created"

# Display results
echo ""
echo -e "${GREEN}🎉 HARBOR DEPLOYMENT COMPLETE! 🎉${NC}"
echo "======================================="
echo ""
echo "🏢 Harbor Information:"
echo "  Harbor URL:   https://$HARBOR_URL"
echo "  Username:     $USERNAME"
echo "  Password:     $PASSWORD"
echo ""
echo "🔧 GitHub Secrets to add:"
echo "  BLACKBOX_REGISTRY_URL=$HARBOR_URL"
echo "  BLACKBOX_REGISTRY_USERNAME=$USERNAME"
echo "  BLACKBOX_REGISTRY_PASSWORD=$PASSWORD"
echo ""
echo "🎯 Next Steps:"
echo "  1. Open https://$HARBOR_URL in your browser"
echo "  2. Login with credentials above"
echo "  3. ⚠️  CHANGE THE DEFAULT PASSWORD!"
echo "  4. Create a project called 'blackbox'"
echo "  5. Add GitHub secrets for CI/CD"
echo "  6. Update DNS to point $HARBOR_URL to your cluster"
echo ""
echo "🧪 Test your Harbor registry:"
echo "  docker login $HARBOR_URL"
echo "  docker tag hello-world:latest $HARBOR_URL/blackbox/hello-world:latest"
echo "  docker push $HARBOR_URL/blackbox/hello-world:latest"
echo ""
echo "📱 Deploy your application:"
echo "  kubectl apply -f k8s-manifests/app/deployment-private-registry.yaml"
echo ""
print_success "Harbor setup completed successfully!"
