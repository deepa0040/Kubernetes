#!/usr/bin/env bash
set -euo pipefail
# To run the script run cmd: DOCKER_USER=shynleaf ./build_image_and_push.sh
# ─────────────────────────────────────────
# Config — override via env or edit below
# ─────────────────────────────────────────
DOCKER_USER="${DOCKER_USER:-}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FRONTEND_IMAGE="frontend"
BACKEND_IMAGE="backend"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/" && pwd)"

# ─────────────────────────────────────────
# Colours
# ─────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()     { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─────────────────────────────────────────
# Usage
# ─────────────────────────────────────────
usage() {
  cat <<EOF
Usage: DOCKER_USER=<dockerhub-username> ./scripts/build-push.sh [OPTIONS]

Options:
  --tag   <tag>        Image tag (default: latest)
  --only  frontend     Build and push frontend only
  --only  backend      Build and push backend only
  --no-push            Build only, skip push
  -h, --help           Show this help

Examples:
  DOCKER_USER=johndoe ./scripts/build-push.sh
  DOCKER_USER=johndoe IMAGE_TAG=v1.0.0 ./scripts/build-push.sh
  DOCKER_USER=johndoe ./scripts/build-push.sh --tag v1.2.0 --only backend
  DOCKER_USER=johndoe ./scripts/build-push.sh --no-push
EOF
  exit 0
}

# ─────────────────────────────────────────
# Parse args
# ─────────────────────────────────────────
ONLY=""
NO_PUSH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)   IMAGE_TAG="$2"; shift 2 ;;
    --only)  ONLY="$2";      shift 2 ;;
    --no-push) NO_PUSH=true; shift ;;
    -h|--help) usage ;;
    *) error "Unknown option: $1"; usage ;;
  esac
done

# ─────────────────────────────────────────
# Validations
# ─────────────────────────────────────────
if [[ -z "$DOCKER_USER" ]]; then
  error "DOCKER_USER is not set."
  echo "  Run: DOCKER_USER=yourusername ./scripts/build-push.sh"
  exit 1
fi

if ! command -v docker &>/dev/null; then
  error "Docker is not installed or not in PATH."
  exit 1
fi

if [[ "$NO_PUSH" == false ]] && ! docker info &>/dev/null; then
  error "Docker daemon is not running."
  exit 1
fi

# ─────────────────────────────────────────
# Login
# ─────────────────────────────────────────
docker_login() {
  if [[ "$NO_PUSH" == true ]]; then
    warn "Skipping Docker Hub login (--no-push mode)."
    return
  fi
  log "Logging into Docker Hub as '${DOCKER_USER}'..."
  if ! docker login --username "$DOCKER_USER"; then
    error "Docker Hub login failed."
    exit 1
  fi
  success "Logged in."
}

# ─────────────────────────────────────────
# Build
# ─────────────────────────────────────────
build_image() {
  local name="$1"       # frontend | backend
  local context="$2"    # path to Dockerfile dir
  local full_image="${DOCKER_USER}/${name}:${IMAGE_TAG}"
  local latest_image="${DOCKER_USER}/${name}:latest"

  log "Building ${full_image} ..."

  if [[ ! -d "$context" ]]; then
    error "Context directory not found: ${context}"
    exit 1
  fi

  docker build \
    --target runner \
    --platform linux/amd64 \
    --cache-from "${full_image}" \
    --label "build.git.sha=$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')" \
    --label "build.date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    -t "${full_image}" \
    -t "${latest_image}" \
    "$context"

  success "Built ${full_image}"
}

# ─────────────────────────────────────────
# Push
# ─────────────────────────────────────────
push_image() {
  local name="$1"
  local full_image="${DOCKER_USER}/${name}:${IMAGE_TAG}"
  local latest_image="${DOCKER_USER}/${name}:latest"

  if [[ "$NO_PUSH" == true ]]; then
    warn "Skipping push for ${full_image} (--no-push mode)."
    return
  fi

  log "Pushing ${full_image} ..."
  docker push "${full_image}"

  if [[ "$IMAGE_TAG" != "latest" ]]; then
    log "Pushing ${latest_image} ..."
    docker push "${latest_image}"
  fi

  success "Pushed ${full_image}"
  echo -e "    ${CYAN}↳ docker pull ${full_image}${NC}"
}

# ─────────────────────────────────────────
# Summary
# ─────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "${GREEN}────────────────────────────────────────${NC}"
  echo -e "${GREEN} Build & Push Complete${NC}"
  echo -e "${GREEN}────────────────────────────────────────${NC}"
  if [[ -z "$ONLY" || "$ONLY" == "frontend" ]]; then
    echo -e "  Frontend : ${CYAN}${DOCKER_USER}/${FRONTEND_IMAGE}:${IMAGE_TAG}${NC}"
  fi
  if [[ -z "$ONLY" || "$ONLY" == "backend" ]]; then
    echo -e "  Backend  : ${CYAN}${DOCKER_USER}/${BACKEND_IMAGE}:${IMAGE_TAG}${NC}"
  fi
  echo -e "  Tag      : ${IMAGE_TAG}"
  echo -e "  Push     : $( [[ "$NO_PUSH" == true ]] && echo 'skipped' || echo 'done' )"
  echo -e "${GREEN}────────────────────────────────────────${NC}"
  echo ""
  if [[ "$NO_PUSH" == false ]]; then
    echo "Update your K8s deployments:"
    if [[ -z "$ONLY" || "$ONLY" == "frontend" ]]; then
      echo "  kubectl set image deployment/frontend frontend=${DOCKER_USER}/${FRONTEND_IMAGE}:${IMAGE_TAG} -n frontend"
    fi
    if [[ -z "$ONLY" || "$ONLY" == "backend" ]]; then
      echo "  kubectl set image deployment/backend backend=${DOCKER_USER}/${BACKEND_IMAGE}:${IMAGE_TAG} -n backend"
    fi
  fi
}

# ─────────────────────────────────────────
# Main
# ─────────────────────────────────────────
main() {
  echo ""
  log "Docker Hub user : ${DOCKER_USER}"
  log "Image tag       : ${IMAGE_TAG}"
  log "Target          : ${ONLY:-all}"
  log "Push            : $( [[ "$NO_PUSH" == true ]] && echo 'no' || echo 'yes' )"
  echo ""

  docker_login

  case "$ONLY" in
    frontend)
      build_image "$FRONTEND_IMAGE" "${PROJECT_ROOT}/frontend"
      push_image  "$FRONTEND_IMAGE"
      ;;
    backend)
      build_image "$BACKEND_IMAGE" "${PROJECT_ROOT}/backend"
      push_image  "$BACKEND_IMAGE"
      ;;
    "")
      build_image "$FRONTEND_IMAGE" "${PROJECT_ROOT}/frontend"
      push_image  "$FRONTEND_IMAGE"
      build_image "$BACKEND_IMAGE"  "${PROJECT_ROOT}/backend"
      push_image  "$BACKEND_IMAGE"
      ;;
    *)
      error "Invalid --only value: '${ONLY}'. Use 'frontend' or 'backend'."
      exit 1
      ;;
  esac

  print_summary
}

main