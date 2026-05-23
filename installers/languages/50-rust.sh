#!/usr/bin/env bash
# installers/languages/50-rust.sh — Rust via rustup (méthode officielle)
# rustup permet la gestion multi-toolchain de façon native

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="languages/rust"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "rust" "install"
log_section "Rust via rustup"

DEVLAB_USER="${DEVLAB_USER:-devuser}"
RUST_VERSION="${RUST_VERSION:-stable}"
USER_HOME=$(getent passwd "$DEVLAB_USER" | cut -d: -f6)
CARGO_HOME="${USER_HOME}/.cargo"

_do_install() {
    if [[ -f "${CARGO_HOME}/bin/rustc" ]]; then
        log_skip "Rust déjà installé (${CARGO_HOME})"
        return 0
    fi

    log_step "Installation rustup + Rust ${RUST_VERSION}..."
    apt_install build-essential

    sudo -u "$DEVLAB_USER" bash -c "
        curl -fsSL '${RUSTUP_INIT_URL:-https://sh.rustup.rs}' | \
            sh -s -- -y --default-toolchain '${RUST_VERSION}' --no-modify-path
    "
    log_ok "Rust installé via rustup"

    # Composants utiles
    sudo -u "$DEVLAB_USER" bash -c "
        source '${CARGO_HOME}/env'
        rustup component add clippy rustfmt
    "
    log_step "Composants : clippy, rustfmt"
}

_configure_path() {
    for rc in "${USER_HOME}/.bashrc" "${USER_HOME}/.zshrc"; do
        if [[ -f "$rc" ]] && ! grep -q "cargo/env" "$rc"; then
            echo '. "$HOME/.cargo/env"' >> "$rc"
            log_step "Cargo env ajouté à $(basename "$rc")"
        fi
    done
}

if state_is_installed "languages/rust"; then
    log_skip "Rust déjà enregistré ($(state_get_version 'languages/rust'))"
    exit 0
fi

_do_install
_configure_path

RUST_VER=$(sudo -u "$DEVLAB_USER" bash -c "source '${CARGO_HOME}/env' && rustc --version 2>/dev/null | awk '{print \$2}'" 2>/dev/null || echo "unknown")
state_set "languages/rust" "$RUST_VER" "installed"
log_ok "Rust ${RUST_VER} prêt"
