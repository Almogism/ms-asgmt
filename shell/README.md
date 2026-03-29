# Bash

Three bash scripts cover the full lifecycle of provisioning and deploying to Azure AKS — from infrastructure creation to image building to Kubernetes deployment.

---

## `init.sh` — Provision Azure Infrastructure

Creates a Resource Group, Azure Container Registry (ACR), and AKS cluster in a single run. Only needs to be run once per environment.

**What it does (in order):**

1. Creates the Resource Group
2. Creates the Container Registry
3. Creates the AKS cluster with Azure CNI networking and ACR attachment
4. Fetches `kubectl` credentials and sets the local context
5. Creates an `AcrPull` role assignment so the cluster can pull images from the registry

**Example:**

```bash
./init.sh --resource-group my-rg --registry myacr
./init.sh -g my-rg -r myacr -l westeurope --node-count 3
```

---

## `build.sh` — Build & Push Docker Images

Builds Docker images for one or more microservices and pushes them to ACR.

**What it does:**

- Resolves the ACR name automatically from the active Azure subscription
- Logs in to ACR via `az acr login`
- For each service: builds a `linux/amd64` image tagged with both the version tag and `:latest`, then pushes both to ACR

Each service must have a directory and a `Dockerfile` under `applications/<service>/`.

**Example:**

```bash
./build.sh
./build.sh --tag v1.2.3 --services service-a
./build.sh --no-push --no-latest
```

---

## `deploy.sh` — Deploy to Kubernetes

Applies Kubernetes manifests to the AKS cluster and waits for rollouts to complete.

**What it does (in order):**

1. Installs the NGINX ingress controller (from the upstream manifest)
2. Applies `namespace.yaml`
3. Applies RBAC manifests — service accounts, roles, and role bindings
4. Applies network policies
5. Substitutes `<ACR_NAME>` in deployment manifests and applies deployments + services for each service
6. Applies ingress rules
7. Waits for each deployment rollout to complete within the timeout


**Example:**

```bash
./deploy.sh
./deploy.sh --tag v1.2.3 --skip-infra
./deploy.sh --dry-run
./deploy.sh --timeout 300 --namespace my-namespace
```

---

## Typical Workflow

```bash
# 1. First time only — provision the infrastructure
./init.sh -g my-rg -r myacr

# 2. Build and push images (run from the repo root or scripts/ directory)
./build.sh --tag v1.0.0

# 3. Deploy to the cluster (first time — includes infra manifests)
./deploy.sh --tag v1.0.0

# 4. Subsequent deployments — skip infra, only roll out new images
./build.sh --tag v1.1.0
./deploy.sh --tag v1.1.0 --skip-infra
```

---

## Requirements

All three scripts require:

- **Azure CLI** (`az`) — logged in with access to the target subscription
- **Docker** — running and accessible (build.sh only)
- **kubectl** — configured and pointing at the target cluster (deploy.sh only)
- **Git** — only if not using `--tag`; used to derive the image tag from the current commit SHA