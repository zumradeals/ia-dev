#!/usr/bin/env bash
# installers/testing/40-phpunit.sh — PHPUnit via Composer global

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="testing/phpunit"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "phpunit" "install"
log_section "PHPUnit"

_do_install() {
    if ! command_exists php; then
        log_fatal "PHP requis — installez d'abord : devlab install languages/php"
    fi
    if ! command_exists composer; then
        log_fatal "Composer requis — installé avec PHP"
    fi

    if command_exists phpunit; then
        log_skip "phpunit déjà installé ($(phpunit --version 2>/dev/null | head -1))"
        return 0
    fi

    log_step "Installation PHPUnit via Composer global..."
    composer global require --quiet phpunit/phpunit

    # Ajouter ~/.composer/vendor/bin au PATH
    local composer_bin="${HOME}/.composer/vendor/bin"
    if [[ ! -L "/usr/local/bin/phpunit" ]]; then
        local phpunit_bin="${composer_bin}/phpunit"
        [[ -f "$phpunit_bin" ]] && ln -sf "$phpunit_bin" /usr/local/bin/phpunit
        log_step "phpunit lié dans /usr/local/bin"
    fi
    log_ok "PHPUnit installé"
}

installer_run \
    "testing/phpunit" \
    "PHPUnit" \
    "phpunit --version 2>/dev/null | head -1 | awk '{print \$2}'" \
    "_do_install"
