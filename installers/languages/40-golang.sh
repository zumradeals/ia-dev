#!/usr/bin/env bash
# installers/languages/40-golang.sh — Go via binaire officiel go.dev/dl
# Permet de contrôler la version exacte sans dépendre d'APT

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="languages/golang"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "golang" "install"
log_section "Go"

GO_INSTALL_DIR="/usr/local/go"
GO_DOWNLOAD_BASE="${GO_DOWNLOAD_BASE:-https://go.dev/dl}"
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) GO_ARCH="amd64" ;;
    aarch64) GO_ARCH="arm64" ;;
    *) log_fatal "Architecture non supportée pour Go : ${ARCH}" ;;
esac

_get_latest_go_version() {
    curl -fsSL "https://go.dev/VERSION?m=text" 2>/dev/null | head -1 | tr -d '\n'
}

_do_install() {
    local go_version="${GO_VERSION:-}"
    if [[ -z "$go_version" ]]; then
        log_step "Récupération de la dernière version stable Go..."
        go_version=$(_get_latest_go_version)
        log_info "Dernière version Go : ${go_version}"
    fi

    local archive="${go_version}.linux-${GO_ARCH}.tar.gz"
    local download_url="${GO_DOWNLOAD_BASE}/${archive}"
    local tmp_file="/tmp/${archive}"

    # Téléchargement
    safe_download "$download_url" "$tmp_file"

    # Suppression ancienne installation si présente
    if [[ -d "$GO_INSTALL_DIR" ]]; then
        log_step "Suppression ancienne installation Go..."
        rm -rf "$GO_INSTALL_DIR"
    fi

    # Extraction
    log_step "Extraction Go dans /usr/local..."
    tar -C /usr/local -xzf "$tmp_file"
    rm -f "$tmp_file"

    log_ok "Go extrait dans ${GO_INSTALL_DIR}"
}

_configure_path() {
    local profile_d="/etc/profile.d/golang.sh"
    if [[ ! -f "$profile_d" ]]; then
        cat > "$profile_d" << 'EOF'
# Go — PATH
export GOROOT=/usr/local/go
export GOPATH="$HOME/go"
export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"
EOF
        log_step "Go ajouté au PATH système (/etc/profile.d/golang.sh)"
    else
        log_skip "PATH Go déjà configuré"
    fi

    # Aussi dans le home de devuser
    DEVLAB_USER="${DEVLAB_USER:-devuser}"
    USER_HOME=$(getent passwd "$DEVLAB_USER" | cut -d: -f6)
    for rc in "${USER_HOME}/.bashrc" "${USER_HOME}/.zshrc"; do
        if [[ -f "$rc" ]] && ! grep -q "GOROOT" "$rc"; then
            cat >> "$rc" << 'EOF'

# Go
export GOROOT=/usr/local/go
export GOPATH="$HOME/go"
export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"
EOF
            log_step "Go ajouté à $(basename "$rc")"
        fi
    done
}

if state_is_installed "languages/golang"; then
    log_skip "Go déjà installé ($(state_get_version 'languages/golang'))"
    exit 0
fi

_do_install
_configure_path

GO_VERSION_INSTALLED=$(/usr/local/go/bin/go version 2>/dev/null | awk '{print $3}' | tr -d 'go')
state_set "languages/golang" "$GO_VERSION_INSTALLED" "installed"
log_ok "Go ${GO_VERSION_INSTALLED} installé"
