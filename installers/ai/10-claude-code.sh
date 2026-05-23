#!/usr/bin/env bash
# installers/ai/10-claude-code.sh — Claude Code CLI (@anthropic-ai/claude-code)
# Requiert Node.js — installe via npm global

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="ai/claude-code"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"
# shellcheck source=../../lib/checks.sh
source "${DEVLAB_ROOT}/lib/checks.sh"

log_init "claude-code" "install"
log_section "Claude Code CLI"

DEVLAB_USER="${DEVLAB_USER:-devuser}"
CLAUDE_PKG="${CLAUDE_CODE_NPM_PKG:-@anthropic-ai/claude-code}"
USER_HOME=$(getent passwd "$DEVLAB_USER" | cut -d: -f6)
NVM_DIR="${USER_HOME}/.nvm"

_check_node_available() {
    if ! sudo -u "$DEVLAB_USER" bash -c "
        export NVM_DIR='${NVM_DIR}'
        [[ -s '${NVM_DIR}/nvm.sh' ]] && source '${NVM_DIR}/nvm.sh'
        command -v node
    " &>/dev/null; then
        log_fatal "Node.js requis — installez d'abord : devlab install languages/nodejs"
    fi
}

_do_install() {
    _check_node_available

    log_step "Installation ${CLAUDE_PKG} via npm..."
    sudo -u "$DEVLAB_USER" bash -c "
        export NVM_DIR='${NVM_DIR}'
        [[ -s '${NVM_DIR}/nvm.sh' ]] && source '${NVM_DIR}/nvm.sh'
        npm install -g '${CLAUDE_PKG}' --quiet
    "
    log_ok "Claude Code CLI installé"
}

if state_is_installed "ai/claude-code"; then
    log_skip "Claude Code déjà installé ($(state_get_version 'ai/claude-code'))"
    exit 0
fi

_do_install

CLAUDE_VER=$(sudo -u "$DEVLAB_USER" bash -c "
    export NVM_DIR='${NVM_DIR}'
    [[ -s '${NVM_DIR}/nvm.sh' ]] && source '${NVM_DIR}/nvm.sh'
    claude --version 2>/dev/null || echo 'unknown'
" 2>/dev/null)

state_set "ai/claude-code" "$CLAUDE_VER" "installed"
log_ok "Claude Code ${CLAUDE_VER} prêt"
echo
log_info "Configurez votre clé API : claude config set api_key YOUR_KEY"
log_info "Ou via variable : export ANTHROPIC_API_KEY=... dans config/secrets.env"
