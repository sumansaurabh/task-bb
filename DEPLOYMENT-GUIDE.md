# 🚀 Harbor Registry Deployment Guide

## Prerequisites

- Kubernetes cluster with kubectl configured
- NGINX Ingress Controller installed
- Cert-Manager for SSL certificates
- Domain name pointing to your cluster
- At least 4GB RAM and 2 CPU cores available

## 🔧 Environment Variables & Configuration

### 1. Update Domain Names

Before deploying, update these files with your actual domain:

#### In `k8s-manifests/blackbox-registry/harbor-registry.yaml`:
```yaml
# Lines to update:
  - host: harbor.bareflux.com        # Change to: harbor.yourdomain.com
    secretName: harbor-tls           # SSL certificate name
```

#### In `k8s-manifests/app/deployment-private-registry.yaml`:
```yaml
# Lines to update:
image: harbor.yourdomain.com/blackbox/backend:latest  # Change yourdomain.com
  - host: your-app.yourdomain.com                     # Change to your app domain
```

#### In `.github/workflows/docker-build-push.yml`:
```yaml
# GitHub Secrets to set:
BLACKBOX_REGISTRY_URL=harbor.yourdomain.com
BLACKBOX_REGISTRY_USERNAME=admin
BLACKBOX_REGISTRY_PASSWORD=Harbor12345  # Change this default password!
```

### 2. Harbor Admin Credentials

Harbor comes with default admin credentials that you should change:

**Default Login:**
- Username: `admin`
- Password: `Harbor12345`

**⚠️ IMPORTANT**: Change the default password immediately after deployment!

### 3. Update Harbor Admin Password

Edit `k8s-manifests/blackbox-registry/harbor-registry.yaml` and update the admin password:

```bash
# Generate new password hash
echo -n "YourNewSecurePassword" | base64

# Update in harbor-registry.yaml:
data:
  password: WW91ck5ld1NlY3VyZVBhc3N3b3Jk  # Replace with your base64 encoded password
```

## 📋 Step-by-Step Harbor Deployment

### Step 1: Deploy Harbor Registry
```bash
# Navigate to your project
cd /Users/sumansaurabh/Documents/blackbox/task-bb

# Deploy Harbor with all components
kubectl apply -f k8s-manifests/blackbox-registry/harbor-registry.yaml

# Check deployment status (Harbor has multiple components)
kubectl get pods -n harbor -w
```

### Step 2: Wait for All Harbor Components
```bash
# Check all pods are running (this may take 5-10 minutes)
kubectl get pods -n harbor

# Expected pods:
# - harbor-database (PostgreSQL)
# - harbor-redis (Redis cache)
# - harbor-core (API server)
# - harbor-registry (Docker registry)
# - harbor-portal (Web UI)

# Check services
kubectl get svc -n harbor

# Check ingress
kubectl get ingress -n harbor
```

### Step 3: Access Harbor Web UI
```bash
# Test Harbor web interface
curl -k https://harbor.yourdomain.com

# Check if all services are ready
kubectl get all -n harbor
```

**First Login:**
1. Open `https://harbor.yourdomain.com` in browser
2. Login with: `admin` / `Harbor12345`
3. **⚠️ IMPORTANT**: Change password immediately!

### Step 4: Configure Harbor
1. **Change Admin Password**:
   - Go to Users → admin → Change Password
   
2. **Create Project**:
   - Projects → New Project
   - Name: `blackbox`
   - Make it public or private as needed

3. **Create Robot Account** (recommended for CI/CD):
   - Projects → blackbox → Robot Accounts
   - Create robot account for GitHub Actions

### Step 5: Configure GitHub Secrets
Go to your GitHub repository → Settings → Secrets and variables → Actions

Add these secrets:
```
BLACKBOX_REGISTRY_URL=harbor.yourdomain.com
BLACKBOX_REGISTRY_USERNAME=admin  
BLACKBOX_REGISTRY_PASSWORD=YourNewPassword
```

### Step 6: Setup Docker Authentication for Kubernetes
```bash
# Create ImagePullSecret for Harbor
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=harbor.yourdomain.com \
  --docker-username=admin \
  --docker-password=YourNewPassword \
  --docker-email=your-email@domain.com \
  --namespace=default

# Or use the setup script (update it first for Harbor)
# ./setup-registry-secret.sh
```

### Step 7: Update Application Deployment
```bash
# Update the image URL in deployment-private-registry.yaml
# Change: image: harbor.yourdomain.com/blackbox/backend:latest
# Then deploy your application
kubectl apply -f k8s-manifests/app/deployment-private-registry.yaml

# Check app deployment
kubectl get pods -n default
```

## 🧪 Testing Your Registry

### Test 1: Push an Image Manually
```bash
# Login to your registry
docker login registry.yourdomain.com
# Username: admin
# Password: your-secure-password

# Tag and push a test image
docker tag hello-world:latest registry.yourdomain.com/test/hello-world:latest
docker push registry.yourdomain.com/test/hello-world:latest
```

### Test 2: Check Web UI
1. Open `https://registry-ui.yourdomain.com` in browser
2. You should see your pushed images
3. Click on repositories to explore

### Test 3: GitHub Workflow
```bash
# Make a change to backend code
echo "console.log('test');" >> backend/server.js

# Commit and push
git add .
git commit -m "test registry workflow"
git push origin main

# Check GitHub Actions tab for workflow execution
# Check registry UI for new images
```

## 🔍 Troubleshooting

### Registry Pod Issues
```bash
# Check registry logs
kubectl logs -n blackbox-registry deployment/blackbox-registry

# Check UI logs  
kubectl logs -n blackbox-registry deployment/registry-ui

# Check events
kubectl get events -n blackbox-registry --sort-by='.lastTimestamp'
```

### Authentication Issues
```bash
# Verify secret content
kubectl get secret registry-auth -n blackbox-registry -o yaml

# Test htpasswd file
echo "YWRtaW46JDJ5..." | base64 -d
```

### DNS/Ingress Issues
```bash
# Check ingress controller
kubectl get pods -n ingress-nginx

# Check certificate
kubectl get cert -n blackbox-registry

# Test DNS resolution
nslookup registry.yourdomain.com
```

### GitHub Workflow Issues
```bash
# Check if secrets are set
# Go to GitHub → Settings → Secrets

# Check workflow logs in GitHub Actions tab

# Test registry connection
docker login registry.yourdomain.com
```

## 📊 Monitoring & Maintenance

### Check Registry Health
```bash
# Registry health endpoint
curl -k https://registry.yourdomain.com/v2/

# Check storage usage
kubectl exec -n blackbox-registry deployment/blackbox-registry -- df -h /var/lib/registry

# View registry logs
kubectl logs -n blackbox-registry deployment/blackbox-registry -f
```

### Cleanup Old Images
```bash
# Access the UI to delete old images
# Or use registry API
curl -X DELETE https://registry.yourdomain.com/v2/repository/tag/reference
```

## 🎯 Quick Commands Reference

```bash
# Deploy registry
kubectl apply -f k8s-manifests/blackbox-registry/registry.yaml

# Check status
kubectl get all -n blackbox-registry

# Setup secrets
./setup-registry-secret.sh

# Deploy app
kubectl apply -f k8s-manifests/app/deployment-private-registry.yaml

# View logs
kubectl logs -n blackbox-registry deployment/blackbox-registry -f

# Delete registry (if needed)
kubectl delete namespace blackbox-registry
```

## 🌐 URLs After Deployment

- **Registry API**: `https://registry.yourdomain.com`
- **Registry Web UI**: `https://registry-ui.yourdomain.com`  
- **Your Application**: `https://your-app.yourdomain.com`

Replace `yourdomain.com` with your actual domain name!
