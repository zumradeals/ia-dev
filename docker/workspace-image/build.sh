#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Build et push l'image GamadCode workspace vers Docker Hub.
#
# Usage:
#   ./build.sh              → build + push zumradeals/gamadcode-workspace:latest
#   ./build.sh v1.2.0       → build + push :v1.2.0 ET :latest
#   ./build.sh --no-push    → build seulement, sans push
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="zumradeals/gamadcode-workspace"
TAG="${1:-latest}"
NO_PUSH=0
[[ "${1:-}" == "--no-push" ]] && NO_PUSH=1 && TAG="latest"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   GamadCode Workspace — Image Build  ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  Image  : ${IMAGE}"
echo "  Tag    : ${TAG}"
echo "  Push   : $([ $NO_PUSH -eq 0 ] && echo 'yes' || echo 'no')"
echo ""

# ── Build ─────────────────────────────────────────────────────────────────────
echo "[1/3] Building ${IMAGE}:${TAG}..."
docker build \
    --pull \
    --tag "${IMAGE}:${TAG}" \
    --label "org.opencontainers.image.title=GamadCode Studio" \
    --label "org.opencontainers.image.description=GamadCode developer workspace" \
    --label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$SCRIPT_DIR"

# Si un tag spécifique est fourni, taguer aussi :latest
if [[ "$TAG" != "latest" ]]; then
    docker tag "${IMAGE}:${TAG}" "${IMAGE}:latest"
    echo "[1/3] Tagged ${IMAGE}:latest"
fi

echo "[2/3] Build terminé ✓"

# ── Test rapide ───────────────────────────────────────────────────────────────
echo "[2/3] Vérification du product.json..."
PATCHED=$(docker run --rm "${IMAGE}:${TAG}" \
    sh -c 'cat "$OPENVSCODE_SERVER_ROOT/product.json"' 2>/dev/null \
    | python3 -c "import json,sys; p=json.load(sys.stdin); print(p.get('nameShort','?'))" 2>/dev/null \
    || echo "vérification manuelle requise")
echo "       nameShort → ${PATCHED}"

# ── Push ─────────────────────────────────────────────────────────────────────
if [[ $NO_PUSH -eq 0 ]]; then
    echo "[3/3] Pushing ${IMAGE}:${TAG}..."
    docker push "${IMAGE}:${TAG}"
    [[ "$TAG" != "latest" ]] && docker push "${IMAGE}:latest"
    echo "[3/3] Push terminé ✓"
else
    echo "[3/3] Push ignoré (--no-push)"
fi

echo ""
echo "✓ Terminé — ${IMAGE}:${TAG}"
echo ""
echo "  Sur le serveur GamadCode, mettre à jour l'image :"
echo "  docker pull ${IMAGE}:${TAG}"
echo "  Puis redémarrer les workspaces utilisateurs via le dashboard /admin"
echo ""
