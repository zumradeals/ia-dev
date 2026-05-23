#!/usr/bin/env bash
# installers/testing/10-playwright.sh — Playwright + navigateurs
# ~600MB — désactivé par défaut dans modules.conf

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="testing/playwright"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "playwright" "install"
log_section "Playwright"

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

    log_step "Installation @playwright/test via npm..."
    sudo -u "$DEVLAB_USER" bash -c "
        export NVM_DIR='${NVM_DIR}'
        [[ -s '${NVM_DIR}/nvm.sh' ]] && source '${NVM_DIR}/nvm.sh'
        npm install -g @playwright/test --quiet
    "

    # Dépendances système pour les navigateurs
    log_step "Installation dépendances navigateurs Playwright..."
    sudo -u "$DEVLAB_USER" bash -c "
        export NVM_DIR='${NVM_DIR}'
        [[ -s '${NVM_DIR}/nvm.sh' ]] && source '${NVM_DIR}/nvm.sh'
        npx playwright install-deps chromium 2>/dev/null || true
        npx playwright install chromium
    "
    log_ok "Playwright + Chromium installés"
}

installer_run \
    "testing/playwright" \
    "Playwright" \
    "npx playwright --version 2>/dev/null | awk '{print \$2}'" \
    "_do_install"
