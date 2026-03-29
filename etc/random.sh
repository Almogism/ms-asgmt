# Check if traffic is allowed
kubectl exec -it <pod> -- bash -c "timeout 5 bash -c 'echo > /dev/tcp/<endpoint_ip>/<endpoint_port>' && echo OPEN || echo BLOCKED"