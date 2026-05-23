#!/usr/bin/env bash
# installers/ai/20-openai-codex.sh — OpenAI Codex CLI
# Requiert Node.js — installe via npm global

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="ai/openai-codex"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "openai-codex" "install"
log_section "OpenAI Codex CLI"

DEVLAB_USER="${DEVLAB_USER:-devuser}"
USER_HOME=$(getent passwd "$DEVLAB_USER" | cut -d: -f6)
NVM_DIR="${USER_HOME}/.nvm"

_do_install() {
    if ! sudo -u "$DEVLAB_USER" bash -c "
        export NVM_DIR='${NVM_DIR}'
        [[ -s '${NVM_DIR}/nvm.sh' ]] && source '${NVM_DIR}/nvm.sh'
        command -v node
    " &>/dev/null; then
        log_fatal "Node.js requis — installez d'abord : devlab install languages/nodejs"
    fi

    log_step "Installation @openai/codex via npm..."
    sudo -u "$DEVLAB_USER" bash -c "
        export NVM_DIR='${NVM_DIR}'
        [[ -s '${NVM_DIR}/nvm.sh' ]] && source '${NVM_DIR}/nvm.sh'
        npm install -g @openai/codex --quiet
    "
}

installer_run \
    "ai/openai-codex" \
    "OpenAI Codex CLI" \
    "codex --version 2>/dev/null || echo 'installed'" \
    "_do_install"

echo
log_info "Configurez votre clé API : export OPENAI_API_KEY=... dans config/secrets.env"
