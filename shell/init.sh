#!/usr/bin/env bash
# =============================================================================
# init.sh — Provision an Azure Resource Group, ACR, and AKS cluster
# =============================================================================
# Usage:
#   ./init.sh [OPTIONS]
#
# Required:
#   -g, --resource-group   NAME    Resource group name (no default)
#   -r, --registry         NAME    ACR name, alphanumeric only (no default)
#
# Optional:
#   -c, --cluster          NAME    AKS cluster name            [default: <resource-group>-aks]
#   -l, --location         LOC     Azure region                [default: israelcentral]
#   -n, --node-count       N       Number of nodes             [default: 2]
#   -s, --node-vm-size     SIZE    VM size for nodes           [default: standard_b2als_v2]
#   -k, --sku              SKU     ACR SKU (Basic|Standard|Premium) [default: Standard]
#       --no-aad                   Disable AAD integration
#       --no-rbac                  Disable Azure RBAC
#   -h, --help                     Show this help message
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
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

# ── Defaults ──────────────────────────────────────────────────────────────────
RESOURCE_GROUP=""
REGISTRY=""
CLUSTER=""           # derived from RESOURCE_GROUP if not set
LOCATION="israelcentral"
NODE_COUNT=2
NODE_VM_SIZE="standard_b2als_v2"
ACR_SKU="Standard"
ENABLE_AAD=true
ENABLE_RBAC=true

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -r|--registry)       REGISTRY="$2";       shift 2 ;;
    -c|--cluster)        CLUSTER="$2";        shift 2 ;;
    -l|--location)       LOCATION="$2";       shift 2 ;;
    -n|--node-count)     NODE_COUNT="$2";     shift 2 ;;
    -s|--node-vm-size)   NODE_VM_SIZE="$2";   shift 2 ;;
    -k|--sku)            ACR_SKU="$2";        shift 2 ;;
    --no-aad)            ENABLE_AAD=false;    shift   ;;
    --no-rbac)           ENABLE_RBAC=false;   shift   ;;
    -h|--help)           usage ;;
    *) die "Unknown argument: $1. Run with --help for usage." ;;
  esac
done

# ── Validation ────────────────────────────────────────────────────────────────
ERRORS=0

if [[ -z "$RESOURCE_GROUP" ]]; then
  error "Missing required argument: --resource-group / -g"
  ERRORS=$((ERRORS + 1))
fi

if [[ -z "$REGISTRY" ]]; then
  error "Missing required argument: --registry / -r"
  ERRORS=$((ERRORS + 1))
fi

if [[ $ERRORS -gt 0 ]]; then
  echo ""
  echo -e "Run ${BLD}$0 --help${RST} for usage."
  exit 1
fi

# ACR names must be alphanumeric only, 5-50 chars
if ! [[ "$REGISTRY" =~ ^[a-zA-Z0-9]{5,50}$ ]]; then
  die "ACR name must be 5-50 alphanumeric characters (no hyphens or underscores)."
fi

# Validate node count is a positive integer
if ! [[ "$NODE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
  die "Node count must be a positive integer, got: $NODE_COUNT"
fi

# Validate ACR SKU
if ! [[ "$ACR_SKU" =~ ^(Basic|Standard|Premium)$ ]]; then
  die "ACR SKU must be one of: Basic, Standard, Premium. Got: $ACR_SKU"
fi

# Derive cluster name if not supplied
if [[ -z "$CLUSTER" ]]; then
  CLUSTER="${RESOURCE_GROUP}-aks"
fi

# ── Pre-flight summary ────────────────────────────────────────────────────────
echo ""
echo -e "${BLD}════════════════════════════════════════════════════════${RST}"
echo -e "${BLD}  AKS Cluster Provisioning — Configuration Summary      ${RST}"
echo -e "${BLD}════════════════════════════════════════════════════════${RST}"
printf "  %-22s %s\n" "Resource Group:"   "$RESOURCE_GROUP"
printf "  %-22s %s\n" "Location:"         "$LOCATION"
printf "  %-22s %s\n" "Container Registry:" "$REGISTRY"
printf "  %-22s %s\n" "ACR SKU:"          "$ACR_SKU"
printf "  %-22s %s\n" "AKS Cluster:"      "$CLUSTER"
printf "  %-22s %s\n" "Node Count:"       "$NODE_COUNT"
printf "  %-22s %s\n" "Node VM Size:"     "$NODE_VM_SIZE"
printf "  %-22s %s\n" "AAD Integration:"  "$ENABLE_AAD"
printf "  %-22s %s\n" "Azure RBAC:"       "$ENABLE_RBAC"
echo -e "${BLD}════════════════════════════════════════════════════════${RST}"
echo ""

# ── Step 1: Resource Group ────────────────────────────────────────────────────
info "Step 1/4 — Creating resource group '${RESOURCE_GROUP}' in '${LOCATION}'..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output table \
  || die "Failed to create resource group '$RESOURCE_GROUP'."
success "Resource group created."
echo ""

# ── Step 2: Container Registry ───────────────────────────────────────────────
info "Step 2/4 — Creating container registry '${REGISTRY}' (SKU: ${ACR_SKU})..."
az acr create \
  --name "$REGISTRY" \
  --resource-group "$RESOURCE_GROUP" \
  --sku "$ACR_SKU" \
  --output table \
  || die "Failed to create ACR '$REGISTRY'."
success "Container registry created."
echo ""

# ── Step 3: AKS Cluster ───────────────────────────────────────────────────────
info "Step 3/4 — Creating AKS cluster '${CLUSTER}' (this may take several minutes)..."

AKS_ARGS=(
  --name "$CLUSTER"
  --resource-group "$RESOURCE_GROUP"
  --node-count "$NODE_COUNT"
  --node-vm-size "$NODE_VM_SIZE"
  --network-plugin azure
  --network-policy azure
  --attach-acr "$REGISTRY"
  --output table
)

if [[ "$ENABLE_AAD" == true ]]; then
  AKS_ARGS+=(--enable-aad)
fi

if [[ "$ENABLE_RBAC" == true ]]; then
  AKS_ARGS+=(--enable-azure-rbac)
fi

az aks create "${AKS_ARGS[@]}" \
  || die "Failed to create AKS cluster '$CLUSTER'."
success "AKS cluster created."
echo ""

# ── Step 4: kubeconfig ────────────────────────────────────────────────────────
info "Step 4/4 — Fetching kubectl credentials for '${CLUSTER}'..."
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER" \
  || die "Failed to retrieve credentials for '$CLUSTER'."
success "kubectl context set to '${CLUSTER}'."
echo ""

# ── Done ──────────────────────────────────────────────────────────────────────
echo -e "${GRN}${BLD}✔  All done! Your cluster is ready.${RST}"
echo -e "   Run ${BLD}kubectl get nodes${RST} to verify."
echo ""