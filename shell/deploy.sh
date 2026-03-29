set -euo pipefail

ACR_NAME=$(az acr list --query "[0].name" --output tsv)

az acr login --name "$ACR_NAME"
ACR_SERVER="${ACR_NAME}.azurecr.io"

IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD)}"
K8S_NAMESPACE="ms-asgmt-app"

sed -i "s|<ACR_NAME>|${ACR_NAME}|g" \
  ../infra/applications/service-a-deployment.yaml \
  ../infra/applications/service-b-deployment.yaml

kubectl set image deployment/service-a \
  service-a="${ACR_SERVER}/service-a:${IMAGE_TAG}" \
  -n "$K8S_NAMESPACE" --dry-run=client -o yaml > /dev/null 2>&1 || true

kubectl set image deployment/service-b \
  service-b="${ACR_SERVER}/service-b:${IMAGE_TAG}" \
  -n "$K8S_NAMESPACE" --dry-run=client -o yaml > /dev/null 2>&1 || true

# Ingress controller creation
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml

# Create namespace
kubectl apply -f ../infra/base/namespace.yaml

# RBAC
kubectl apply -f ../infra/base/rbac/service-accounts.yaml
kubectl apply -f ../infra/base/rbac/roles.yaml
kubectl apply -f ../infra/base/rbac/role-bindings.yaml

# Define network policies
kubectl apply -f ../infra/base/network-policies/entries.yaml

# Create deployments & services
kubectl apply -f ../infra/applications/service-a-deployment.yaml
kubectl apply -f ../infra/applications/service-a-svc.yaml
kubectl apply -f ../infra/applications/service-b-deployment.yaml
kubectl apply -f ../infra/applications/service-b-svc.yaml

# Ingress rules
kubectl apply -f ../infra/base/ingress.yaml

# ── Wait for rollout ──────────────────────────────────────────────────────────
echo ""
echo "  Waiting for rollouts to complete…"
kubectl rollout status deployment/service-a -n "$K8S_NAMESPACE" --timeout=120s
kubectl rollout status deployment/service-b -n "$K8S_NAMESPACE" --timeout=120s

# ── Print ingress IP ──────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════"
echo " Deployment complete ✓"
INGRESS_IP=$(kubectl get svc ingress-nginx-controller \
  -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "<pending>")
echo " Ingress IP : $INGRESS_IP"
echo " Service A  : http://$INGRESS_IP/service-a/"
echo " Service B  : http://$INGRESS_IP/service-b/"
echo "════════════════════════════════════════════════"