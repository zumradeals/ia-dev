#!/usr/bin/env bash
# installers/languages/20-python.sh — Python 3 + pip + venv + pipx

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="languages/python"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "python" "install"
log_section "Python 3"

PYTHON_VERSION="${PYTHON_VERSION:-3.12}"

_do_install() {
    apt_install \
        "python${PYTHON_VERSION}" \
        "python${PYTHON_VERSION}-venv" \
        "python${PYTHON_VERSION}-dev" \
        "python3-pip" \
        "python3-full" \
        "pipx"

    # Symlinks python3 → python si absents
    if ! command_exists python && ! command_exists python3; then
        log_warn "python3 introuvable après installation — vérifier l'APT"
        return 1
    fi

    if ! command_exists python && command_exists python3; then
        update-alternatives --install /usr/bin/python python /usr/bin/python3 1 2>/dev/null || true
        log_step "Alias python → python3 créé"
    fi

    # pipx dans PATH
    pipx ensurepath 2>/dev/null || true

    log_ok "Python 3 + pip + venv + pipx installés"
}

installer_run \
    "languages/python" \
    "Python ${PYTHON_VERSION}" \
    "python3 --version 2>/dev/null | awk '{print \$2}'" \
    "_do_install"
