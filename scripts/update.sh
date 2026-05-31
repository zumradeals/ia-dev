#!/usr/bin/env bash
# scripts/update.sh — Mise à jour du système et des outils DevLab

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="update"

# shellcheck source=../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../lib/checks.sh
source "${DEVLAB_ROOT}/lib/checks.sh"

require_root
log_init "update" "maintenance"
log_section "Mise à jour DevLab"

# ─── Migration config ─────────────────────────
bash "${DEVLAB_ROOT}/scripts/migrate-config.sh"

DEVLAB_USER="${DEVLAB_USER:-devuser}"
USER_HOME=$(getent passwd "$DEVLAB_USER" | cut -d: -f6)
NVM_DIR="${USER_HOME}/.nvm"

# ─── APT ─────────────────────────────────────
log_section "Mise à jour APT"
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
log_ok "APT mis à jour"

# ─── Node.js ─────────────────────────────────
if [[ -f "${NVM_DIR}/nvm.sh" ]]; then
    log_section "Mise à jour Node.js/npm"
    sudo -u "$DEVLAB_USER" bash -c "
        export NVM_DIR='${NVM_DIR}'
        source '${NVM_DIR}/nvm.sh'
        nvm install '${NODE_LTS_ALIAS:-lts/iron}' 2>/dev/null
        nvm use default
        npm update -g --quiet 2>/dev/null || true
        echo 'Node.js : '\$(node --version)
    " || log_warn "Mise à jour Node.js échouée"
fi

# ─── Python pip ──────────────────────────────
if command_exists pip3; then
    log_section "Mise à jour pip"
    pip3 install --quiet --upgrade pip 2>/dev/null || true
    log_ok "pip mis à jour"
fi

# ─── Composer ────────────────────────────────
if command_exists composer; then
    log_section "Mise à jour Composer"
    composer self-update --quiet 2>/dev/null || log_warn "Composer self-update échoué"
    log_ok "Composer mis à jour"
fi

# ─── Rust ────────────────────────────────────
if [[ -f "${USER_HOME}/.cargo/bin/rustup" ]]; then
    log_section "Mise à jour Rust"
    sudo -u "$DEVLAB_USER" bash -c "
        source '${USER_HOME}/.cargo/env'
        rustup update quiet 2>/dev/null
        echo 'Rust : '\$(rustc --version)
    " || log_warn "Mise à jour Rust échouée"
fi

# ─── Claude Code ─────────────────────────────
if [[ -f "${NVM_DIR}/nvm.sh" ]]; then
    if sudo -u "$DEVLAB_USER" bash -c "
        export NVM_DIR='${NVM_DIR}'
        source '${NVM_DIR}/nvm.sh'
        command -v claude
    " &>/dev/null; then
        log_section "Mise à jour Claude Code"
        sudo -u "$DEVLAB_USER" bash -c "
            export NVM_DIR='${NVM_DIR}'
            source '${NVM_DIR}/nvm.sh'
            npm update -g @anthropic-ai/claude-code --quiet 2>/dev/null || true
        " || log_warn "Mise à jour Claude Code échouée"
        log_ok "Claude Code mis à jour"
    fi
fi

# ─── Oh My Zsh ───────────────────────────────
OMZ_DIR="${USER_HOME}/.oh-my-zsh"
if [[ -d "$OMZ_DIR" ]]; then
    log_section "Mise à jour Oh My Zsh"
    sudo -u "$DEVLAB_USER" bash -c "
        cd '${OMZ_DIR}' && git pull --quiet origin master 2>/dev/null
    " || log_warn "Mise à jour Oh My Zsh échouée"
    log_ok "Oh My Zsh mis à jour"
fi

# ─── fzf ─────────────────────────────────────
FZF_DIR="${USER_HOME}/.fzf"
if [[ -d "$FZF_DIR" ]]; then
    log_section "Mise à jour fzf"
    sudo -u "$DEVLAB_USER" bash -c "
        cd '${FZF_DIR}' && git pull --quiet origin master 2>/dev/null
        '${FZF_DIR}/install' --all --no-update-rc --key-bindings --completion 2>/dev/null
    " || log_warn "Mise à jour fzf échouée"
    log_ok "fzf mis à jour"
fi

# ─── Nettoyage ───────────────────────────────
log_section "Nettoyage"
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -qq
DEBIAN_FRONTEND=noninteractive apt-get autoclean -qq
log_ok "Nettoyage terminé"

log_ok "Mise à jour complète terminée"
