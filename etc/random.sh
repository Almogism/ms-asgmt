# Check if traffic is allowed
kubectl exec -it <pod> -- bash -c "timeout 5 bash -c 'echo > /dev/tcp/<endpoint_ip>/<endpoint_port>' && echo OPEN || echo BLOCKED"

# Create service principal (similar to service account)
az ad sp create-for-rbac \
  --name "github-actions-acr" \
  --role contributor \
  --scopes /subscriptions/<YOUR_SUBSCRIPTION_ID>/resourceGroups/<YOUR_RESOURCE_GROUP> \
  --sdk-auth