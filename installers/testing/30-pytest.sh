#!/usr/bin/env bash
# installers/testing/30-pytest.sh — Pytest + plugins essentiels

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="testing/pytest"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "pytest" "install"
log_section "Pytest"

_do_install() {
    if ! command_exists python3; then
        log_fatal "Python 3 requis — installez d'abord : devlab install languages/python"
    fi

    local packages=("pytest" "pytest-cov" "pytest-asyncio" "pytest-xdist" "httpx")

    for pkg in "${packages[@]}"; do
        if python3 -c "import ${pkg//-/_}" &>/dev/null; then
            log_skip "pip : ${pkg} déjà disponible"
        else
            log_step "pip install ${pkg}..."
            pip3 install --quiet --break-system-packages "$pkg" 2>/dev/null || \
                pip3 install --quiet "$pkg"
        fi
    done
    log_ok "Pytest et plugins installés"
}

installer_run \
    "testing/pytest" \
    "Pytest" \
    "pytest --version 2>/dev/null | awk '{print \$2}'" \
    "_do_install"
