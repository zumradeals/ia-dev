#!/usr/bin/env bash
# installers/languages/10-nodejs.sh — Node.js LTS via nvm + pnpm
# nvm garantit l'idempotence et la gestion multi-versions

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="languages/nodejs"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"
# shellcheck source=../../lib/checks.sh
source "${DEVLAB_ROOT}/lib/checks.sh"

log_init "nodejs" "install"
log_section "Node.js LTS via nvm"

DEVLAB_USER="${DEVLAB_USER:-devuser}"
NVM_VERSION="${NVM_VERSION:-0.39.7}"
NODE_LTS_ALIAS="${NODE_LTS_ALIAS:-lts/iron}"
USER_HOME=$(getent passwd "$DEVLAB_USER" | cut -d: -f6)
NVM_DIR="${USER_HOME}/.nvm"

_install_nvm() {
    if [[ -f "${NVM_DIR}/nvm.sh" ]]; then
        log_skip "nvm déjà présent (${NVM_DIR})"
        return 0
    fi

    log_step "Installation nvm ${NVM_VERSION}..."
    local nvm_install_url="https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh"

    sudo -u "$DEVLAB_USER" bash -c "
        export NVM_DIR='${NVM_DIR}'
        curl -fsSL '${nvm_install_url}' | bash
    "
    log_ok "nvm installé"
}

_install_node() {
    log_step "Installation Node.js ${NODE_LTS_ALIAS}..."
    sudo -u "$DEVLAB_USER" bash -c "
        export NVM_DIR='${NVM_DIR}'
        source '${NVM_DIR}/nvm.sh'
        if nvm ls '${NODE_LTS_ALIAS}' 2>/dev/null | grep -q 'N/A'; then
            nvm install '${NODE_LTS_ALIAS}'
        else
            echo 'Node.js ${NODE_LTS_ALIAS} déjà installé dans nvm'
        fi
        nvm alias default '${NODE_LTS_ALIAS}'
        nvm use default
    "
    log_ok "Node.js installé"
}

_install_pnpm() {
    if sudo -u "$DEVLAB_USER" bash -c "source '${NVM_DIR}/nvm.sh' && command -v pnpm" &>/dev/null; then
        log_skip "pnpm déjà installé"
        return 0
    fi

    log_step "Installation pnpm..."
    sudo -u "$DEVLAB_USER" bash -c "
        export NVM_DIR='${NVM_DIR}'
        source '${NVM_DIR}/nvm.sh'
        npm install -g pnpm --quiet
    "
    log_ok "pnpm installé"
}

_configure_shell_integration() {
    # Ajouter nvm au .bashrc et .zshrc de façon idempotente
    local nvm_snippet='
# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'

    for rc_file in "${USER_HOME}/.bashrc" "${USER_HOME}/.zshrc"; do
        if [[ -f "$rc_file" ]]; then
            if ! grep -q "NVM_DIR" "$rc_file"; then
                echo "$nvm_snippet" >> "$rc_file"
                log_step "nvm ajouté à $(basename "$rc_file")"
            else
                log_skip "nvm déjà dans $(basename "$rc_file")"
            fi
        fi
    done
}

# ── Exécution ─────────────────────────────────
if state_is_installed "languages/nodejs"; then
    NODE_VER=$(state_get_version "languages/nodejs")
    log_skip "Node.js déjà installé (${NODE_VER}) selon le registre"
    exit 0
fi

apt_install curl

_install_nvm
_install_node
_install_pnpm
_configure_shell_integration

NODE_VERSION_INSTALLED=$(sudo -u "$DEVLAB_USER" bash -c "
    export NVM_DIR='${NVM_DIR}'
    source '${NVM_DIR}/nvm.sh'
    node --version 2>/dev/null || echo unknown
")

state_set "languages/nodejs" "$NODE_VERSION_INSTALLED" "installed"
log_ok "Node.js ${NODE_VERSION_INSTALLED} prêt"
log_info "Rechargez votre shell ou : source ~/.bashrc"
