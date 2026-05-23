#!/usr/bin/env bash
# installers/devtools/30-fzf.sh — fzf (fuzzy finder) via dépôt git officiel
# Installation via git clone garantit la dernière version + intégrations shell

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="devtools/fzf"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "fzf" "install"
log_section "fzf (fuzzy finder)"

DEVLAB_USER="${DEVLAB_USER:-devuser}"
USER_HOME=$(getent passwd "$DEVLAB_USER" | cut -d: -f6)
FZF_DIR="${USER_HOME}/.fzf"

_do_install() {
    if [[ -d "$FZF_DIR" ]]; then
        log_info "fzf déjà cloné — mise à jour..."
        sudo -u "$DEVLAB_USER" git -C "$FZF_DIR" pull --quiet origin master 2>/dev/null || true
    else
        log_step "Clonage fzf..."
        sudo -u "$DEVLAB_USER" git clone --depth=1 \
            "${FZF_REPO:-https://github.com/junegunn/fzf.git}" \
            "$FZF_DIR" --quiet
    fi

    # Installation avec intégrations shell
    sudo -u "$DEVLAB_USER" bash -c "
        '${FZF_DIR}/install' --all --no-update-rc --key-bindings --completion
    "

    # Ajouter aux RC files si pas déjà présent
    for rc in "${USER_HOME}/.bashrc" "${USER_HOME}/.zshrc"; do
        if [[ -f "$rc" ]] && ! grep -q "fzf" "$rc"; then
            echo '[ -f ~/.fzf.'$(basename "$rc" | tr -d '.')' ] && source ~/.fzf.'$(basename "$rc" | tr -d '.')'' >> "$rc"
            log_step "fzf ajouté à $(basename "$rc")"
        fi
    done
    log_ok "fzf installé avec intégrations shell"
}

installer_run \
    "devtools/fzf" \
    "fzf" \
    "fzf --version 2>/dev/null | awk '{print \$1}'" \
    "_do_install"
