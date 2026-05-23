#!/usr/bin/env bash
# installers/devtools/40-modern-cli.sh — Outils CLI modernes : ripgrep, bat, eza

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="devtools/modern-cli"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "modern-cli" "install"
log_section "Outils CLI modernes"

DEVLAB_USER="${DEVLAB_USER:-devuser}"
USER_HOME=$(getent passwd "$DEVLAB_USER" | cut -d: -f6)
ARCH=$(uname -m)

_install_ripgrep() {
    if command_exists rg; then
        log_skip "ripgrep déjà installé ($(rg --version 2>/dev/null | head -1 | awk '{print $2}'))"
        return 0
    fi
    log_step "Installation ripgrep..."
    apt_install ripgrep
}

_install_bat() {
    if command_exists bat || command_exists batcat; then
        log_skip "bat déjà installé"
        return 0
    fi
    log_step "Installation bat..."
    apt_install bat

    # Sur Ubuntu, bat s'installe comme 'batcat' — créer un alias
    if command_exists batcat && ! command_exists bat; then
        ln -sf "$(which batcat)" /usr/local/bin/bat
        log_step "Alias bat → batcat créé"
    fi
}

_install_eza() {
    if command_exists eza; then
        log_skip "eza déjà installé ($(eza --version 2>/dev/null | head -1 | awk '{print $2}'))"
        return 0
    fi

    log_step "Installation eza..."

    # eza via dépôt officiel
    local keyfile="/etc/apt/keyrings/gierens.gpg"
    local listfile="/etc/apt/sources.list.d/gierens.list"

    if [[ ! -f "$listfile" ]]; then
        curl -fsSL "https://raw.githubusercontent.com/eza-community/eza/main/deb.asc" | \
            gpg --dearmor -o "$keyfile" 2>/dev/null
        echo "deb [signed-by=${keyfile}] http://deb.gierens.de stable main" > "$listfile"
        apt_update
    fi

    apt_install eza
}

_install_delta() {
    # delta — git diff amélioré
    if command_exists delta; then
        log_skip "delta déjà installé"
        return 0
    fi

    log_step "Installation delta..."
    local arch_str
    case "$ARCH" in
        x86_64) arch_str="amd64" ;;
        aarch64) arch_str="arm64" ;;
        *) log_warn "Architecture non supportée pour delta : ${ARCH}"; return 0 ;;
    esac

    local latest_url
    latest_url=$(curl -fsSL "https://api.github.com/repos/dandavison/delta/releases/latest" 2>/dev/null | \
        grep "browser_download_url" | grep "${arch_str}.deb" | head -1 | cut -d'"' -f4)

    if [[ -n "$latest_url" ]]; then
        safe_download "$latest_url" "/tmp/delta.deb"
        DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/delta.deb > /dev/null 2>&1
        rm -f /tmp/delta.deb
        log_ok "delta installé"
    else
        log_warn "delta : URL de téléchargement non trouvée"
    fi
}

_configure_git_delta() {
    if ! command_exists delta; then
        return 0
    fi

    # Configurer delta pour git de façon idempotente
    sudo -u "$DEVLAB_USER" bash -c '
        git config --global core.pager "delta" 2>/dev/null
        git config --global interactive.diffFilter "delta --color-only" 2>/dev/null
        git config --global delta.navigate true 2>/dev/null
        git config --global delta.light false 2>/dev/null
        git config --global merge.conflictstyle diff3 2>/dev/null
    ' || true
    log_step "delta configuré comme pager git"
}

_setup_shell_aliases() {
    local aliases_file="${USER_HOME}/.shell_aliases"
    if [[ ! -f "$aliases_file" ]]; then
        cat > "$aliases_file" << 'EOF'
# DevLab — aliases CLI modernes
alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first'
alias la='eza -a --icons'
alias lt='eza --tree --icons --level=2'
alias cat='bat --paging=never'
alias grep='rg'
EOF
        chown "${DEVLAB_USER}:$(id -gn "$DEVLAB_USER")" "$aliases_file"
        log_step "Aliases modernes créés : ${aliases_file}"
    fi

    for rc in "${USER_HOME}/.bashrc" "${USER_HOME}/.zshrc"; do
        if [[ -f "$rc" ]]; then
            append_if_missing '[[ -f ~/.shell_aliases ]] && source ~/.shell_aliases' "$rc"
        fi
    done
}

_do_install() {
    _install_ripgrep
    _install_bat
    _install_eza
    _install_delta
    _configure_git_delta
    _setup_shell_aliases
}

installer_run \
    "devtools/modern-cli" \
    "CLI modernes (rg, bat, eza, delta)" \
    "echo 'bundle-'$(date +%Y%m%d)" \
    "_do_install"
