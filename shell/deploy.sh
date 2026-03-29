#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Deploy microservices to an AKS cluster via kubectl
# =============================================================================
# Usage:
#   ./deploy.sh [OPTIONS]
#
# Optional:
#   -t, --tag          TAG       Image tag to deploy        [default: git short SHA]
#   -n, --namespace    NAME      Kubernetes namespace        [default: ms-asgmt-app]
#   -i, --infra-dir    PATH      Path to the infra directory [default: ../infra]
#   -s, --services     LIST      Comma-separated services    [default: service-a,service-b]
#       --skip-infra             Skip ingress controller, namespace, RBAC, and
#                                network-policy manifests (apply app manifests only)
#       --skip-ingress           Skip ingress controller installation
#       --dry-run                Print what would be applied without making changes
#       --timeout      SECONDS   Rollout wait timeout        [default: 120]
#   -h, --help                   Show this help message
#
# Requirements:
#   - Azure CLI (az) logged in with access to an ACR
#   - kubectl configured and pointing at the target cluster
#   - (Default) Must be run from a git repository for auto SHA tagging
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YEL='\033[1;33m'
GRN='\033[0;32m'
CYN='\033[0;36m'
BLD='\033[1m'
RST='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo -e "${CYN}[INFO]${RST}  $*"; }
success() { echo -e "${GRN}[OK]${RST}    $*"; }
warn()    { echo -e "${YEL}[WARN]${RST}  $*"; }
error()   { echo -e "${RED}[ERROR]${RST} $*" >&2; }
die()     { error "$*"; exit 1; }

usage() {
  sed -n '/^# Usage:/,/^# ===/p' "$0" | sed 's/^# \{0,2\}//' | sed '/^====/d'
  exit 0
}

kubectl_apply() {
  local label="$1"
  local target="$2"   # file path or URL

  info "Applying ${label}..."
  if [[ "$DRY_RUN" == true ]]; then
    warn "[dry-run] kubectl apply -f ${target} --dry-run=client"
    kubectl apply -f "$target" --dry-run=client
  else
    kubectl apply -f "$target" \
      || die "Failed to apply ${label}: '${target}'"
  fi
  success "Applied: ${label}"
}

# ── Defaults ──────────────────────────────────────────────────────────────────
IMAGE_TAG=""
K8S_NAMESPACE="ms-asgmt-app"
INFRA_DIR="../infra"
SERVICES="service-a,service-b"
SKIP_INFRA=false
SKIP_INGRESS=false
DRY_RUN=false
ROLLOUT_TIMEOUT=120

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--tag)          IMAGE_TAG="$2";         shift 2 ;;
    -n|--namespace)    K8S_NAMESPACE="$2";     shift 2 ;;
    -i|--infra-dir)    INFRA_DIR="$2";         shift 2 ;;
    -s|--services)     SERVICES="$2";          shift 2 ;;
    --skip-infra)      SKIP_INFRA=true;        shift   ;;
    --skip-ingress)    SKIP_INGRESS=true;      shift   ;;
    --dry-run)         DRY_RUN=true;           shift   ;;
    --timeout)         ROLLOUT_TIMEOUT="$2";   shift 2 ;;
    -h|--help)         usage ;;
    *) die "Unknown argument: $1. Run with --help for usage." ;;
  esac
done

# ── Pre-flight checks ─────────────────────────────────────────────────────────
if ! command -v az &>/dev/null; then
  die "Azure CLI (az) is not installed or not in PATH."
fi

if ! command -v kubectl &>/dev/null; then
  die "kubectl is not installed or not in PATH."
fi

if ! kubectl cluster-info &>/dev/null; then
  die "kubectl cannot reach the cluster. Check your kubeconfig / VPN."
fi

# Validate timeout is a positive integer
if ! [[ "$ROLLOUT_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  die "Timeout must be a positive integer (seconds), got: $ROLLOUT_TIMEOUT"
fi

# ── Resolve image tag ─────────────────────────────────────────────────────────
if [[ -z "$IMAGE_TAG" ]]; then
  if ! command -v git &>/dev/null; then
    die "git is not installed and no --tag was provided. Cannot determine image tag."
  fi
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    die "Not inside a git repository. Use --tag to provide an explicit image tag."
  fi
  IMAGE_TAG=$(git rev-parse --short HEAD)
fi

# ── Resolve ACR ───────────────────────────────────────────────────────────────
info "Resolving ACR name from Azure subscription..."
ACR_NAME=$(az acr list --query "[0].name" --output tsv 2>/dev/null || true)

if [[ -z "$ACR_NAME" ]]; then
  die "No Azure Container Registry found in the current subscription. Are you logged in? (az login)"
fi

ACR_SERVER="${ACR_NAME}.azurecr.io"
success "Found ACR: ${ACR_SERVER}"

# ── Validate infra directory ──────────────────────────────────────────────────
if [[ ! -d "$INFRA_DIR" ]]; then
  die "Infra directory not found: '$INFRA_DIR'. Use --infra-dir to specify the correct path."
fi

# ── Parse and validate services ───────────────────────────────────────────────
IFS=',' read -ra SERVICE_LIST <<< "$SERVICES"

if [[ ${#SERVICE_LIST[@]} -eq 0 ]]; then
  die "No services specified. Use --services to provide a comma-separated list."
fi

ERRORS=0
for SERVICE in "${SERVICE_LIST[@]}"; do
  for MANIFEST in \
    "${INFRA_DIR}/applications/${SERVICE}-deployment.yaml" \
    "${INFRA_DIR}/applications/${SERVICE}-svc.yaml"; do
    if [[ ! -f "$MANIFEST" ]]; then
      error "Required manifest not found: '$MANIFEST'"
      ERRORS=$((ERRORS + 1))
    fi
  done
done

if [[ $ERRORS -gt 0 ]]; then
  echo ""
  echo -e "Run ${BLD}$0 --help${RST} for usage."
  exit 1
fi

# Validate infra base manifests (only if not skipping)
if [[ "$SKIP_INFRA" == false ]]; then
  for MANIFEST in \
    "${INFRA_DIR}/base/namespace.yaml" \
    "${INFRA_DIR}/base/rbac/service-accounts.yaml" \
    "${INFRA_DIR}/base/rbac/roles.yaml" \
    "${INFRA_DIR}/base/rbac/role-bindings.yaml" \
    "${INFRA_DIR}/base/network-policies/entries.yaml" \
    "${INFRA_DIR}/base/ingress.yaml"; do
    if [[ ! -f "$MANIFEST" ]]; then
      error "Required manifest not found: '$MANIFEST'"
      ERRORS=$((ERRORS + 1))
    fi
  done
fi

if [[ $ERRORS -gt 0 ]]; then
  echo ""
  echo -e "Run ${BLD}$0 --help${RST} for usage."
  exit 1
fi

# ── ACR Login ─────────────────────────────────────────────────────────────────
info "Logging in to ACR '${ACR_NAME}'..."
az acr login --name "$ACR_NAME" \
  || die "Failed to log in to ACR '$ACR_NAME'."
success "ACR login successful."

# ── Substitute ACR name in deployment manifests ───────────────────────────────
info "Substituting ACR name in deployment manifests..."
for SERVICE in "${SERVICE_LIST[@]}"; do
  MANIFEST="${INFRA_DIR}/applications/${SERVICE}-deployment.yaml"
  sed -i "s|<ACR_NAME>|${ACR_NAME}|g" "$MANIFEST"
  success "Patched: ${MANIFEST}"
done

# ── Pre-flight summary ────────────────────────────────────────────────────────
echo ""
echo -e "${BLD}════════════════════════════════════════════════════════${RST}"
echo -e "${BLD}  Kubernetes Deploy — Configuration Summary             ${RST}"
echo -e "${BLD}════════════════════════════════════════════════════════${RST}"
printf "  %-22s %s\n" "ACR:"              "$ACR_SERVER"
printf "  %-22s %s\n" "Image Tag:"        "$IMAGE_TAG"
printf "  %-22s %s\n" "Namespace:"        "$K8S_NAMESPACE"
printf "  %-22s %s\n" "Services:"         "${SERVICE_LIST[*]}"
printf "  %-22s %s\n" "Infra Dir:"        "$INFRA_DIR"
printf "  %-22s %s\n" "Skip Infra:"       "$SKIP_INFRA"
printf "  %-22s %s\n" "Skip Ingress:"     "$SKIP_INGRESS"
printf "  %-22s %s\n" "Dry Run:"          "$DRY_RUN"
printf "  %-22s %s\n" "Rollout Timeout:"  "${ROLLOUT_TIMEOUT}s"
echo -e "${BLD}════════════════════════════════════════════════════════${RST}"
echo ""

# ── Step 1: Ingress controller ────────────────────────────────────────────────
if [[ "$SKIP_INFRA" == false && "$SKIP_INGRESS" == false ]]; then
  info "Step 1 — Installing NGINX ingress controller..."
  INGRESS_MANIFEST="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml"
  if [[ "$DRY_RUN" == true ]]; then
    warn "[dry-run] kubectl apply -f ${INGRESS_MANIFEST} --dry-run=client"
  else
    kubectl apply -f "$INGRESS_MANIFEST" \
      || die "Failed to install NGINX ingress controller."
  fi
  success "NGINX ingress controller applied."
  echo ""
else
  warn "Skipping ingress controller installation."
  echo ""
fi

# ── Step 2: Namespace ─────────────────────────────────────────────────────────
if [[ "$SKIP_INFRA" == false ]]; then
  info "Step 2 — Applying namespace..."
  kubectl_apply "namespace" "${INFRA_DIR}/base/namespace.yaml"
  echo ""

  # ── Step 3: RBAC ─────────────────────────────────────────────────────────────
  info "Step 3 — Applying RBAC manifests..."
  kubectl_apply "service accounts"  "${INFRA_DIR}/base/rbac/service-accounts.yaml"
  kubectl_apply "roles"             "${INFRA_DIR}/base/rbac/roles.yaml"
  kubectl_apply "role bindings"     "${INFRA_DIR}/base/rbac/role-bindings.yaml"
  echo ""

  # ── Step 4: Network policies ──────────────────────────────────────────────────
  info "Step 4 — Applying network policies..."
  kubectl_apply "network policies" "${INFRA_DIR}/base/network-policies/entries.yaml"
  echo ""
else
  warn "Skipping infra manifests (--skip-infra was set)."
  echo ""
fi

# ── Step 5: Application deployments & services ────────────────────────────────
STEP=5
TOTAL=${#SERVICE_LIST[@]}
CURRENT=0

info "Step ${STEP} — Deploying application services..."
echo ""

for SERVICE in "${SERVICE_LIST[@]}"; do
  CURRENT=$((CURRENT + 1))
  echo -e "${BLD}── Service ${CURRENT}/${TOTAL}: ${SERVICE} ──────────────────────────────────────${RST}"

  kubectl_apply "${SERVICE} deployment" "${INFRA_DIR}/applications/${SERVICE}-deployment.yaml"
  kubectl_apply "${SERVICE} service"    "${INFRA_DIR}/applications/${SERVICE}-svc.yaml"
  echo ""
done

# ── Step 6: Ingress rules ─────────────────────────────────────────────────────
if [[ "$SKIP_INFRA" == false ]]; then
  info "Step 6 — Applying ingress rules..."
  kubectl_apply "ingress rules" "${INFRA_DIR}/base/ingress.yaml"
  echo ""
fi

# ── Step 7: Wait for rollouts ─────────────────────────────────────────────────
if [[ "$DRY_RUN" == true ]]; then
  warn "Skipping rollout wait (--dry-run was set)."
  echo ""
else
  info "Step 7 — Waiting for rollouts to complete (timeout: ${ROLLOUT_TIMEOUT}s)..."
  echo ""
  ROLLOUT_ERRORS=0

  for SERVICE in "${SERVICE_LIST[@]}"; do
    info "Waiting for deployment/${SERVICE}..."
    if kubectl rollout status "deployment/${SERVICE}" \
        -n "$K8S_NAMESPACE" \
        --timeout="${ROLLOUT_TIMEOUT}s"; then
      success "deployment/${SERVICE} is ready."
    else
      error "Rollout timed out or failed for deployment/${SERVICE}."
      ROLLOUT_ERRORS=$((ROLLOUT_ERRORS + 1))
    fi
  done

  if [[ $ROLLOUT_ERRORS -gt 0 ]]; then
    echo ""
    die "${ROLLOUT_ERRORS} rollout(s) failed. Run 'kubectl describe deployment -n ${K8S_NAMESPACE}' for details."
  fi
  echo ""
fi

# ── Done — print ingress summary ──────────────────────────────────────────────
INGRESS_IP=$(kubectl get svc ingress-nginx-controller \
  -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "<pending>")

echo -e "${GRN}${BLD}✔  Deployment complete!${RST}"
echo ""
echo -e "${BLD}════════════════════════════════════════════════════════${RST}"
printf "  %-14s %s\n" "Ingress IP:"   "$INGRESS_IP"
for SERVICE in "${SERVICE_LIST[@]}"; do
  printf "  %-14s %s\n" "${SERVICE}:" "http://${INGRESS_IP}/${SERVICE}/"
done
echo -e "${BLD}════════════════════════════════════════════════════════${RST}"

if [[ "$INGRESS_IP" == "<pending>" ]]; then
  echo ""
  warn "Ingress IP is still pending. Run the following to check once it's assigned:"
  echo -e "   ${BLD}kubectl get svc ingress-nginx-controller -n ingress-nginx${RST}"
fi
echo ""