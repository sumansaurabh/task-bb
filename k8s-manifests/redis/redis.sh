#!/bin/bash
set -euo pipefail

# Config
NAMESPACE="default"
RELEASE_NAME="redis"
REDIS_USER="admin"

# Ask password from user
read -sp "Enter Redis password: " REDIS_PASS
echo
if [[ -z "$REDIS_PASS" ]]; then
  echo "❌ Password cannot be empty"
  exit 1
fi

# Add Bitnami repo if missing
if ! helm repo list | grep -q "bitnami"; then
  echo "👉 Adding Bitnami Helm repo..."
  helm repo add bitnami https://charts.bitnami.com/bitnami
  helm repo update
fi

# Create namespace if not exists
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"

echo "🚀 Installing Redis in namespace $NAMESPACE..."
helm upgrade --install $RELEASE_NAME bitnami/redis \
  --namespace $NAMESPACE \
  --set architecture=standalone \
  --set auth.enabled=true \
  --set auth.username=$REDIS_USER \
  --set auth.password=$REDIS_PASS \
  --set replica.replicaCount=1 \
  --set master.persistence.size=5Gi \
  --set replica.persistence.size=5Gi \
  --set master.service.type=LoadBalancer \
  --set replica.service.type=ClusterIP

echo "⏳ Waiting for Redis pods to be ready..."
kubectl rollout status statefulset/${RELEASE_NAME}-master -n $NAMESPACE

# Fetch connection info
PRIVATE_URL="redis://$REDIS_USER:$REDIS_PASS@${RELEASE_NAME}-master.${NAMESPACE}.svc.cluster.local:6379"
PUBLIC_IP=$(kubectl get svc ${RELEASE_NAME}-master -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
PUBLIC_URL="redis://$REDIS_USER:$REDIS_PASS@$PUBLIC_IP:6379"

echo "✅ Redis installed!"
echo "Private URL (inside cluster): $PRIVATE_URL"
echo "Public URL  (outside cluster): $PUBLIC_URL"

# Store in Vault
echo "🔑 Writing Redis URLs into Vault..."
vault kv put secret/app REDIS_URL="$PRIVATE_URL" REDIS_PUBLIC_URL="$PUBLIC_URL"

echo "🎉 Done! Redis is ready with both public & private endpoints."
