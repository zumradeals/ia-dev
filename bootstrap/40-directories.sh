#!/usr/bin/env bash
# bootstrap/40-directories.sh — Création de l'arborescence /devlab/
# Idempotent : ensure_dir ne recrée pas ce qui existe

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="directories"

# shellcheck source=../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

require_root
log_init "directories" "bootstrap"
log_section "Création de l'arborescence DevLab"

DEVLAB_USER="${DEVLAB_USER:-devuser}"
DEVLAB_GROUP="${DEVLAB_GROUP:-devlab}"

# Répertoires et leurs permissions
# Format : "chemin:owner:permissions"
declare -A DIRS=(
    ["${DEVLAB_ROOT}/workspace/projects"]="${DEVLAB_USER}:755"
    ["${DEVLAB_ROOT}/workspace/sandboxes"]="${DEVLAB_USER}:755"
    ["${DEVLAB_ROOT}/repositories"]="${DEVLAB_USER}:755"
    ["${DEVLAB_ROOT}/logs/bootstrap"]="root:755"
    ["${DEVLAB_ROOT}/logs/install"]="${DEVLAB_USER}:755"
    ["${DEVLAB_ROOT}/logs/maintenance"]="${DEVLAB_USER}:755"
    ["${DEVLAB_ROOT}/logs/errors"]="${DEVLAB_USER}:755"
    ["${DEVLAB_ROOT}/backups/configs"]="${DEVLAB_USER}:700"
    ["${DEVLAB_ROOT}/backups/databases"]="${DEVLAB_USER}:700"
    ["${DEVLAB_ROOT}/state"]="${DEVLAB_USER}:700"
    ["${DEVLAB_ROOT}/config"]="root:750"
)

for dir in "${!DIRS[@]}"; do
    local_spec="${DIRS[$dir]}"
    owner="${local_spec%%:*}"
    perms="${local_spec##*:}"

    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        chown "${owner}:${DEVLAB_GROUP}" "$dir"
        chmod "$perms" "$dir"
        log_step "Créé : ${dir} (${owner}, ${perms})"
    else
        # Met à jour propriétaire/permissions si nécessaire
        chown "${owner}:${DEVLAB_GROUP}" "$dir" 2>/dev/null || true
        chmod "$perms" "$dir" 2>/dev/null || true
        log_debug "Existant : ${dir}"
    fi
done

# ── Répertoire principal DEVLAB_ROOT ──────────
chown "root:${DEVLAB_GROUP}" "${DEVLAB_ROOT}"
chmod 755 "${DEVLAB_ROOT}"

# ── Initialisation du registre d'état ─────────
log_info "Initialisation du registre d'état..."
STATE_FILE="${DEVLAB_ROOT}/state/registry.json"

if [[ ! -f "$STATE_FILE" || "$(jq '._meta.created' "$STATE_FILE" 2>/dev/null)" == '""' ]]; then
    _ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    _host=$(hostname -f 2>/dev/null || hostname)
    cat > "$STATE_FILE" << REGISTRY
{
  "_meta": {
    "version": "1.0",
    "created": "${_ts}",
    "updated": "${_ts}",
    "devlab_version": "1.0.0",
    "host": "${_host}"
  },
  "modules": {}
}
REGISTRY
    chown "${DEVLAB_USER}:${DEVLAB_GROUP}" "$STATE_FILE"
    chmod 640 "$STATE_FILE"
    log_ok "Registre initialisé"
else
    log_skip "Registre déjà initialisé"
fi

# ── Lien symbolique /devlab → DEVLAB_ROOT si différent ──
if [[ "${DEVLAB_ROOT}" != "/devlab" && ! -L "/devlab" ]]; then
    if confirm "Créer lien symbolique /devlab → ${DEVLAB_ROOT} ?"; then
        ln -sf "${DEVLAB_ROOT}" "/devlab"
        log_ok "Lien symbolique créé : /devlab → ${DEVLAB_ROOT}"
    fi
fi

# ── devlab dans PATH global ───────────────────
PROFILE_D="/etc/profile.d/devlab.sh"
if [[ ! -f "$PROFILE_D" ]]; then
    cat > "$PROFILE_D" << PROFILE
# DevLab — Variables d'environnement système
export DEVLAB_ROOT="${DEVLAB_ROOT}"
export PATH="\${DEVLAB_ROOT}/bin:\${PATH}"
PROFILE
    log_ok "Variables d'environnement : /etc/profile.d/devlab.sh"
else
    log_skip "profile.d/devlab.sh déjà présent"
fi

state_set "bootstrap.directories" "$(date +%Y%m%d)" "installed"
log_ok "Arborescence DevLab configurée"
echo
log_info "Racine : ${DEVLAB_ROOT}"
log_info "Workspace : ${DEVLAB_ROOT}/workspace"
log_info "Logs : ${DEVLAB_ROOT}/logs"
