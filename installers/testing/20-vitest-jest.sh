#!/usr/bin/env bash
# installers/testing/20-vitest-jest.sh — Vitest + Jest globaux via npm

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="testing/vitest-jest"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "vitest-jest" "install"
log_section "Vitest + Jest"

DEVLAB_USER="${DEVLAB_USER:-devuser}"
USER_HOME=$(getent passwd "$DEVLAB_USER" | cut -d: -f6)
NVM_DIR="${USER_HOME}/.nvm"

_npm_run() {
    sudo -u "$DEVLAB_USER" bash -c "
        export NVM_DIR='${NVM_DIR}'
        [[ -s '${NVM_DIR}/nvm.sh' ]] && source '${NVM_DIR}/nvm.sh'
        $*
    "
}

_do_install() {
    if ! _npm_run "command -v node" &>/dev/null; then
        log_fatal "Node.js requis — installez d'abord : devlab install languages/nodejs"
    fi

    # Vitest
    if _npm_run "command -v vitest" &>/dev/null; then
        log_skip "vitest déjà installé"
    else
        log_step "Installation vitest..."
        _npm_run "npm install -g vitest --quiet"
        log_ok "vitest installé"
    fi

    # Jest
    if _npm_run "command -v jest" &>/dev/null; then
        log_skip "jest déjà installé"
    else
        log_step "Installation jest..."
        _npm_run "npm install -g jest @jest/globals --quiet"
        log_ok "jest installé"
    fi
}

installer_run \
    "testing/vitest-jest" \
    "Vitest + Jest" \
    "echo 'vitest+jest'" \
    "_do_install"
