# Microsoft Assignment

## Required Setup Steps

### 1. Install Azure CLI

Download and install the Azure CLI: [Link](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest
)

### 2. Log in to Azure

```bash
az login
```

### 3. Install `kubectl` via Azure CLI

```bash
az aks install-cli
```

This installs `kubectl` and `kubelogin` — required for communicating with AKS clusters. Might require `sudo`.

### 4. Enable Auto-Install of CLI Extensions (optional)

```bash
az config set extension.use_dynamic_install=yes_without_prompt
```

### 5. Register Providers (new Azure subscription only)

```bash
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.ContainerService
```

### Verify Registration

Registration may take a few moments. Check the status with:

```bash
az provider show --namespace Microsoft.ContainerRegistry --query "registrationState"
az provider show --namespace Microsoft.ContainerService --query "registrationState"
```

Wait until both return `"Registered"` before proceeding.

### 6. Install kubectx/kubens (optional)

These tools makes switching between k8s clusters and namespaces easier: [Link](https://github.com/ahmetb/kubectx?tab=readme-ov-file#installation)