#!/usr/bin/env bash
# installers/containers/20-compose.sh — Docker Compose v2 (plugin intégré)
# Docker Compose v2 est un plugin docker — installé avec docker-compose-plugin

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="containers/compose"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "compose" "install"
log_section "Docker Compose v2"

_do_install() {
    if docker compose version &>/dev/null; then
        local ver; ver=$(docker compose version | awk '{print $NF}')
        log_skip "Docker Compose déjà disponible (${ver})"
        return 0
    fi

    # docker-compose-plugin doit avoir été installé par 10-docker.sh
    if ! command -v docker &>/dev/null; then
        log_fatal "Docker non installé — lancez d'abord containers/docker"
    fi

    # Installer le plugin si manquant
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-compose-plugin
    log_ok "docker-compose-plugin installé"
}

installer_run \
    "containers/compose" \
    "Docker Compose v2" \
    "docker compose version 2>/dev/null | awk '{print \$NF}'" \
    "_do_install"
