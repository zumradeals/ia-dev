#!/usr/bin/env bash
# scripts/sync.sh — Réconcilie le registre d'état avec la réalité système
# Utile si des outils ont été installés/désinstallés manuellement hors DevLab

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="sync"

# shellcheck source=../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../lib/checks.sh
source "${DEVLAB_ROOT}/lib/checks.sh"
# shellcheck source=../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "sync" "maintenance"
log_section "Synchronisation registre ↔ système"

DEVLAB_USER="${DEVLAB_USER:-devuser}"
USER_HOME=$(getent passwd "$DEVLAB_USER" | cut -d: -f6)
NVM_DIR="${USER_HOME}/.nvm"

_node_version() {
    sudo -u "$DEVLAB_USER" bash -c "
        export NVM_DIR='${NVM_DIR}'
        [[ -s '${NVM_DIR}/nvm.sh' ]] && source '${NVM_DIR}/nvm.sh'
        node --version 2>/dev/null || echo ''
    " 2>/dev/null
}

declare -A tool_checks=(
    ["base/system-tools"]="command -v git"
    ["languages/nodejs"]="[[ -d '${NVM_DIR}' ]]"
    ["languages/python"]="command -v python3"
    ["languages/php"]="command -v php"
    ["languages/golang"]="[[ -f /usr/local/go/bin/go ]]"
    ["languages/rust"]="[[ -f '${USER_HOME}/.cargo/bin/rustc' ]]"
    ["containers/docker"]="command -v docker"
    ["containers/compose"]="docker compose version"
    ["databases/postgresql"]="command -v psql"
    ["databases/redis"]="command -v redis-cli"
    ["web/nginx"]="command -v nginx"
    ["ai/claude-code"]="command -v claude || true"
    ["devtools/zsh"]="command -v zsh"
    ["devtools/tmux"]="command -v tmux"
    ["devtools/fzf"]="[[ -d '${USER_HOME}/.fzf' ]]"
    ["devtools/modern-cli"]="command -v rg"
)

SYNCED=0
MISSING=0
STALE=0

for module in "${!tool_checks[@]}"; do
    check="${tool_checks[$module]}"
    actually_installed=false

    if eval "$check" &>/dev/null; then
        actually_installed=true
    fi

    in_registry=false
    state_is_installed "$module" && in_registry=true || true

    if $actually_installed && ! $in_registry; then
        printf "  ${C_YELLOW}+${C_RESET} %-35s installé mais absent du registre\n" "$module"
        state_set "$module" "synced" "installed"
        (( SYNCED++ )) || true
    elif ! $actually_installed && $in_registry; then
        printf "  ${C_RED}-${C_RESET} %-35s dans le registre mais non trouvé\n" "$module"
        state_remove "$module"
        (( STALE++ )) || true
    elif $actually_installed && $in_registry; then
        printf "  ${C_GREEN}✔${C_RESET} %-35s OK\n" "$module"
    else
        printf "  ${C_DIM}✗${C_RESET} %-35s non installé\n" "$module"
        (( MISSING++ )) || true
    fi
done

echo
log_info "Synchronisés : ${SYNCED} | Obsolètes retirés : ${STALE} | Non installés : ${MISSING}"
log_ok "Synchronisation terminée"
