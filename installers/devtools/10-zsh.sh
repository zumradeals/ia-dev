#!/usr/bin/env bash
# installers/devtools/10-zsh.sh — Zsh + Oh My Zsh + plugins essentiels

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="devtools/zsh"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "zsh" "install"
log_section "Zsh + Oh My Zsh"

DEVLAB_USER="${DEVLAB_USER:-devuser}"
USER_HOME=$(getent passwd "$DEVLAB_USER" | cut -d: -f6)
OMZ_DIR="${USER_HOME}/.oh-my-zsh"

_install_zsh() {
    apt_install zsh
    # Définir zsh comme shell de devuser si pas encore fait
    local current_shell; current_shell=$(getent passwd "$DEVLAB_USER" | cut -d: -f7)
    if [[ "$current_shell" != "/usr/bin/zsh" && "$current_shell" != "$(which zsh)" ]]; then
        chsh -s "$(which zsh)" "$DEVLAB_USER"
        log_step "Shell par défaut → zsh pour ${DEVLAB_USER}"
    else
        log_skip "zsh déjà shell par défaut"
    fi
}

_install_omz() {
    if [[ -d "$OMZ_DIR" ]]; then
        log_skip "Oh My Zsh déjà installé (${OMZ_DIR})"
        return 0
    fi

    log_step "Installation Oh My Zsh..."
    sudo -u "$DEVLAB_USER" bash -c "
        RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c \"\$(curl -fsSL '${OMZ_INSTALL_URL:-https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh}')\"
    "
    log_ok "Oh My Zsh installé"
}

_install_omz_plugins() {
    local omz_custom="${OMZ_DIR}/custom/plugins"

    # zsh-autosuggestions
    local autosugg="${omz_custom}/zsh-autosuggestions"
    if [[ ! -d "$autosugg" ]]; then
        log_step "Plugin zsh-autosuggestions..."
        sudo -u "$DEVLAB_USER" git clone --depth=1 \
            "https://github.com/zsh-users/zsh-autosuggestions" \
            "$autosugg" --quiet
    else
        log_skip "zsh-autosuggestions déjà installé"
    fi

    # zsh-syntax-highlighting
    local syntax="${omz_custom}/zsh-syntax-highlighting"
    if [[ ! -d "$syntax" ]]; then
        log_step "Plugin zsh-syntax-highlighting..."
        sudo -u "$DEVLAB_USER" git clone --depth=1 \
            "https://github.com/zsh-users/zsh-syntax-highlighting" \
            "$syntax" --quiet
    else
        log_skip "zsh-syntax-highlighting déjà installé"
    fi

    log_ok "Plugins Oh My Zsh installés"
}

_configure_zshrc() {
    local zshrc="${USER_HOME}/.zshrc"
    local template="${DEVLAB_ROOT}/configs/zsh/.zshrc.tpl"
    local aliases_src="${DEVLAB_ROOT}/configs/zsh/aliases.zsh.tpl"
    local aliases_dest="${USER_HOME}/.zsh_aliases"

    if [[ -f "$template" ]]; then
        if [[ ! -f "$zshrc" ]]; then
            render_template "$template" "$zshrc"
            chown "${DEVLAB_USER}:$(id -gn "$DEVLAB_USER")" "$zshrc"
            log_step ".zshrc configuré depuis template"
        else
            # Injecter les blocs essentiels manquants dans le .zshrc existant
            local user_group; user_group=$(id -gn "$DEVLAB_USER")

            # export ZSH manquant (cause l'erreur /oh-my-zsh.sh)
            if ! grep -q 'export ZSH=' "$zshrc"; then
                sed -i '1s|^|export ZSH="$HOME/.oh-my-zsh"\n|' "$zshrc"
                log_step ".zshrc : export ZSH ajouté"
            fi

            # NVM manquant
            if ! grep -q 'NVM_DIR' "$zshrc"; then
                cat >> "$zshrc" << 'NVM'

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
NVM
                log_step ".zshrc : bloc NVM ajouté"
            fi

            # DEVLAB_ROOT manquant
            if ! grep -q 'DEVLAB_ROOT' "$zshrc"; then
                cat >> "$zshrc" << DEVLAB

# DevLab
export DEVLAB_ROOT="${DEVLAB_ROOT}"
export PATH="${DEVLAB_ROOT}/bin:\$PATH"
DEVLAB
                log_step ".zshrc : DEVLAB_ROOT ajouté"
            fi

            chown "${DEVLAB_USER}:${user_group}" "$zshrc"
            log_skip ".zshrc : blocs essentiels vérifiés/complétés"
        fi
    fi

    if [[ -f "$aliases_src" && ! -f "$aliases_dest" ]]; then
        render_template "$aliases_src" "$aliases_dest"
        chown "${DEVLAB_USER}:$(id -gn "$DEVLAB_USER")" "$aliases_dest"
        log_step "Aliases installés : ${aliases_dest}"
    fi
}

_do_install() {
    _install_zsh
    _install_omz
    _install_omz_plugins
    _configure_zshrc
}

installer_run \
    "devtools/zsh" \
    "Zsh + Oh My Zsh" \
    "zsh --version 2>/dev/null | awk '{print \$2}'" \
    "_do_install"
