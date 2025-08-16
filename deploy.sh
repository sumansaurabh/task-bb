#!/bin/bash

# Deploy RBAC configuration first
echo "Applying RBAC configuration..."
kubectl apply -f k8s-rbac.yaml

# Wait a moment for RBAC to be processed
sleep 2

# Deploy the application
echo "Applying deployment configuration..."
kubectl apply -f deployment-infra.yaml

echo "Deployment complete!"
echo ""
echo "To check the status:"
echo "kubectl get pods -l app=nodejs-app"
echo "kubectl get serviceaccount lro-service-account"
echo "kubectl describe role pod-patcher"
