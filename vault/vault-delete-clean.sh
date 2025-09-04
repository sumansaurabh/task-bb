#!/bin/bash

# Complete Bank-Vaults cleanup script
echo "🧹 Starting complete Bank-Vaults cleanup..."

# Delete the Vault custom resource
echo "Deleting Vault instance..."
kubectl delete vault vault --timeout=60s 2>/dev/null || true

# Delete any remaining vault pods forcefully
echo "Force deleting vault pods..."
kubectl delete pods -l app.kubernetes.io/name=vault --force --grace-period=0 2>/dev/null || true

# Delete PVCs (persistent volume claims)
echo "Deleting persistent volume claims..."
kubectl delete pvc -l app.kubernetes.io/name=vault 2>/dev/null || true

# Delete services
echo "Deleting vault services..."
kubectl delete svc vault 2>/dev/null || true
kubectl delete svc vault-active 2>/dev/null || true

# Delete secrets
echo "Deleting vault secrets..."
kubectl delete secret vault-unseal-keys 2>/dev/null || true
kubectl delete secret vault-tls 2>/dev/null || true

# Delete configmaps
echo "Deleting vault configmaps..."
kubectl delete configmap vault-config 2>/dev/null || true

# Delete RBAC resources
echo "Deleting RBAC resources..."
kubectl delete clusterrolebinding vault 2>/dev/null || true
kubectl delete clusterrole vault 2>/dev/null || true
kubectl delete rolebinding vault 2>/dev/null || true
kubectl delete role vault 2>/dev/null || true
kubectl delete serviceaccount vault 2>/dev/null || true

# Delete Vault Secrets Webhook
echo "Deleting Vault Secrets Webhook..."
helm uninstall vault-secrets-webhook -n vault-infra 2>/dev/null || true

# Delete Vault Operator
echo "Deleting Vault Operator..."
helm uninstall vault-operator 2>/dev/null || true

# Delete namespace
echo "Deleting vault-infra namespace..."
kubectl delete namespace vault-infra --timeout=60s 2>/dev/null || true

# Clean up any remaining CRDs if needed
echo "Checking for remaining Bank-Vaults CRDs..."
kubectl get crd | grep vault.banzaicloud.com || echo "No Bank-Vaults CRDs found"

# Wait a moment for cleanup to complete
echo "Waiting for cleanup to complete..."
sleep 10

# Verify cleanup
echo ""
echo "🔍 Verifying cleanup:"
echo "Remaining vault pods:"
kubectl get pods -l app.kubernetes.io/name=vault 2>/dev/null || echo "No vault pods found ✅"

echo "Remaining vault resources:"
kubectl get vault 2>/dev/null || echo "No vault resources found ✅"

echo "Remaining PVCs:"
kubectl get pvc | grep vault || echo "No vault PVCs found ✅"

echo ""
echo "✅ Bank-Vaults cleanup complete!"
echo "You can now run the fixed deployment script."