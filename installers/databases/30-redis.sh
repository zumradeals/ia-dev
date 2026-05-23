#!/usr/bin/env bash
# installers/databases/30-redis.sh — Redis via dépôt officiel redis.io

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="databases/redis"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "redis" "install"
log_section "Redis"

REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_BIND="${REDIS_BIND:-127.0.0.1}"

_add_redis_repo() {
    local keyfile="/etc/apt/keyrings/redis-archive-keyring.gpg"
    local listfile="/etc/apt/sources.list.d/redis.list"

    if [[ -f "$listfile" ]]; then
        log_skip "Dépôt Redis déjà configuré"
        return 0
    fi

    apt_install curl gnupg
    mkdir -p /etc/apt/keyrings

    curl -fsSL "https://packages.redis.io/gpg" | \
        gpg --dearmor -o "$keyfile"
    chmod a+r "$keyfile"

    # shellcheck source=/dev/null
    source /etc/os-release
    echo "deb [signed-by=${keyfile}] https://packages.redis.io/deb ${VERSION_CODENAME} main" \
        > "$listfile"
    apt_update
    log_ok "Dépôt Redis configuré"
}

_install_redis() {
    apt_install redis
}

_configure_redis() {
    local redis_conf="/etc/redis/redis.conf"
    backup_file "$redis_conf"

    local template="${DEVLAB_ROOT}/configs/redis/redis.conf.tpl"
    if [[ -f "$template" ]]; then
        render_template "$template" "$redis_conf"
    else
        # Hardening inline minimal
        sed -i "s/^bind .*/bind ${REDIS_BIND}/" "$redis_conf"
        sed -i "s/^port .*/port ${REDIS_PORT}/" "$redis_conf"
        # Désactiver les commandes dangereuses
        grep -qE "^rename-command FLUSHALL" "$redis_conf" || \
            echo "rename-command FLUSHALL \"\"" >> "$redis_conf"
        grep -qE "^rename-command CONFIG" "$redis_conf" || \
            echo "rename-command CONFIG DEVLAB_REDIS_CONFIG" >> "$redis_conf"
    fi

    systemctl enable redis-server --quiet
    systemctl restart redis-server
    log_ok "Redis démarré sur ${REDIS_BIND}:${REDIS_PORT}"
}

_do_install() {
    _add_redis_repo
    _install_redis
    _configure_redis
}

installer_run \
    "databases/redis" \
    "Redis" \
    "redis-cli --version 2>/dev/null | awk '{print \$2}'" \
    "_do_install"

# Test de connectivité
if redis-cli -p "$REDIS_PORT" ping 2>/dev/null | grep -q PONG; then
    log_ok "Redis répond PONG"
else
    log_warn "Redis installé mais pas encore accessible sur port ${REDIS_PORT}"
fi
