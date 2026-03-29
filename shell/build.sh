#!/usr/bin/env bash
# =============================================================================
# build.sh — Build and push Docker images to Azure Container Registry
# =============================================================================
# Usage:
#   ./build.sh [OPTIONS]
#
# Optional:
#   -t, --tag          TAG       Image tag to use          [default: git short SHA]
#   -s, --services     LIST      Comma-separated list of services to build
#                                                          [default: service-a,service-b]
#   -a, --app-dir      PATH      Path to the applications directory
#                                                          [default: ../applications]
#       --no-push                Build images but do not push to ACR
#       --no-latest              Do not tag images as :latest
#   -h, --help                   Show this help message
#
# Requirements:
#   - Azure CLI (az) logged in with access to an ACR
#   - Docker running and accessible
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

# ── Defaults ──────────────────────────────────────────────────────────────────
IMAGE_TAG=""           # resolved later (git SHA or --tag)
SERVICES="service-a,service-b"
APP_DIR="../applications"
PUSH=true
TAG_LATEST=true

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--tag)       IMAGE_TAG="$2";  shift 2 ;;
    -s|--services)  SERVICES="$2";   shift 2 ;;
    -a|--app-dir)   APP_DIR="$2";    shift 2 ;;
    --no-push)      PUSH=false;      shift   ;;
    --no-latest)    TAG_LATEST=false; shift  ;;
    -h|--help)      usage ;;
    *) die "Unknown argument: $1. Run with --help for usage." ;;
  esac
done

# ── Pre-flight checks ─────────────────────────────────────────────────────────
if ! command -v az &>/dev/null; then
  die "Azure CLI (az) is not installed or not in PATH."
fi

if ! command -v docker &>/dev/null; then
  die "Docker is not installed or not in PATH."
fi

if ! docker info &>/dev/null; then
  die "Docker daemon is not running or not accessible."
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

# ── Validate app directory ────────────────────────────────────────────────────
if [[ ! -d "$APP_DIR" ]]; then
  die "Applications directory not found: '$APP_DIR'. Use --app-dir to specify the correct path."
fi

# ── Parse services list ───────────────────────────────────────────────────────
IFS=',' read -ra SERVICE_LIST <<< "$SERVICES"

if [[ ${#SERVICE_LIST[@]} -eq 0 ]]; then
  die "No services specified. Use --services to provide a comma-separated list."
fi

# Validate that each service directory and Dockerfile exist
ERRORS=0
for SERVICE in "${SERVICE_LIST[@]}"; do
  SERVICE_DIR="${APP_DIR}/${SERVICE}"
  DOCKERFILE="${SERVICE_DIR}/Dockerfile"

  if [[ ! -d "$SERVICE_DIR" ]]; then
    error "Service directory not found: '$SERVICE_DIR'"
    ERRORS=$((ERRORS + 1))
  elif [[ ! -f "$DOCKERFILE" ]]; then
    error "Dockerfile not found for service '$SERVICE': '$DOCKERFILE'"
    ERRORS=$((ERRORS + 1))
  fi
done

if [[ $ERRORS -gt 0 ]]; then
  echo ""
  echo -e "Run ${BLD}$0 --help${RST} for usage."
  exit 1
fi

# ── Pre-flight summary ────────────────────────────────────────────────────────
echo ""
echo -e "${BLD}════════════════════════════════════════════════════════${RST}"
echo -e "${BLD}  Docker Build & Push — Configuration Summary           ${RST}"
echo -e "${BLD}════════════════════════════════════════════════════════${RST}"
printf "  %-22s %s\n" "ACR:"              "$ACR_SERVER"
printf "  %-22s %s\n" "Image Tag:"        "$IMAGE_TAG"
printf "  %-22s %s\n" "Services:"         "${SERVICE_LIST[*]}"
printf "  %-22s %s\n" "Applications Dir:" "$APP_DIR"
printf "  %-22s %s\n" "Push to ACR:"      "$PUSH"
printf "  %-22s %s\n" "Tag as :latest:"   "$TAG_LATEST"
echo -e "${BLD}════════════════════════════════════════════════════════${RST}"
echo ""

# ── ACR Login ─────────────────────────────────────────────────────────────────
info "Logging in to ACR '${ACR_NAME}'..."
az acr login --name "$ACR_NAME" \
  || die "Failed to log in to ACR '$ACR_NAME'."
success "ACR login successful."
echo ""

# ── Build & Push ──────────────────────────────────────────────────────────────
TOTAL=${#SERVICE_LIST[@]}
CURRENT=0

for SERVICE in "${SERVICE_LIST[@]}"; do
  CURRENT=$((CURRENT + 1))
  SERVICE_DIR="${APP_DIR}/${SERVICE}"
  DOCKERFILE="${SERVICE_DIR}/Dockerfile"
  VERSIONED_TAG="${ACR_SERVER}/${SERVICE}:${IMAGE_TAG}"
  LATEST_TAG="${ACR_SERVER}/${SERVICE}:latest"

  echo -e "${BLD}── Service ${CURRENT}/${TOTAL}: ${SERVICE} ──────────────────────────────────────${RST}"

  # Build
  info "Building image '${VERSIONED_TAG}'..."

  BUILD_ARGS=(
    --platform linux/amd64
    --tag "$VERSIONED_TAG"
    --file "$DOCKERFILE"
  )

  if [[ "$TAG_LATEST" == true ]]; then
    BUILD_ARGS+=(--tag "$LATEST_TAG")
  fi

  BUILD_ARGS+=("$SERVICE_DIR")

  docker build "${BUILD_ARGS[@]}" \
    || die "Failed to build image for service '$SERVICE'."
  success "Image built: ${VERSIONED_TAG}"

  # Push
  if [[ "$PUSH" == true ]]; then
    info "Pushing '${VERSIONED_TAG}'..."
    docker push "$VERSIONED_TAG" \
      || die "Failed to push '${VERSIONED_TAG}'."
    success "Pushed: ${VERSIONED_TAG}"

    if [[ "$TAG_LATEST" == true ]]; then
      info "Pushing '${LATEST_TAG}'..."
      docker push "$LATEST_TAG" \
        || die "Failed to push '${LATEST_TAG}'."
      success "Pushed: ${LATEST_TAG}"
    fi
  else
    warn "Skipping push (--no-push was set)."
  fi

  echo ""
done

# ── Done ──────────────────────────────────────────────────────────────────────
echo -e "${GRN}${BLD}✔  All done!${RST}"
if [[ "$PUSH" == true ]]; then
  echo -e "   Images are available in ACR under tag: ${BLD}${IMAGE_TAG}${RST}"
else
  echo -e "   Images were built locally but ${YEL}not pushed${RST} (--no-push was set)."
fi
echo ""