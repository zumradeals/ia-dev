#!/usr/bin/env bash
# installers/languages/30-php.sh — PHP 8.x + extensions + Composer
# Utilise le PPA Ondrej qui fournit les versions récentes de PHP

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="languages/php"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"
# shellcheck source=../../lib/checks.sh
source "${DEVLAB_ROOT}/lib/checks.sh"

log_init "php" "install"
log_section "PHP ${PHP_VERSION:-8.3}"

PHP_VERSION="${PHP_VERSION:-8.3}"
DEVLAB_USER="${DEVLAB_USER:-devuser}"

_add_ondrej_ppa() {
    local ppa_list="/etc/apt/sources.list.d/ondrej-ubuntu-php-noble.list"
    if [[ -f "$ppa_list" ]]; then
        log_skip "PPA Ondrej/PHP déjà configuré"
        return 0
    fi

    log_step "Ajout PPA Ondrej/PHP..."
    apt_install software-properties-common
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1
    apt_update
    log_ok "PPA Ondrej/PHP ajouté"
}

_install_php() {
    local php_packages=(
        "php${PHP_VERSION}"
        "php${PHP_VERSION}-cli"
        "php${PHP_VERSION}-fpm"
        "php${PHP_VERSION}-common"
        "php${PHP_VERSION}-curl"
        "php${PHP_VERSION}-mbstring"
        "php${PHP_VERSION}-xml"
        "php${PHP_VERSION}-zip"
        "php${PHP_VERSION}-json"
        "php${PHP_VERSION}-pgsql"
        "php${PHP_VERSION}-mysql"
        "php${PHP_VERSION}-redis"
        "php${PHP_VERSION}-gd"
        "php${PHP_VERSION}-intl"
        "php${PHP_VERSION}-bcmath"
        "php${PHP_VERSION}-tokenizer"
    )
    apt_install "${php_packages[@]}"
    log_ok "PHP ${PHP_VERSION} et extensions installés"
}

_install_composer() {
    if command_exists composer; then
        log_skip "Composer déjà installé ($(composer --version --no-ansi 2>/dev/null | head -1))"
        return 0
    fi

    log_step "Installation Composer..."
    local composer_setup="/tmp/composer-setup.php"
    local expected_sig
    expected_sig=$(curl -fsSL https://composer.github.io/installer.sig)

    curl -fsSL https://getcomposer.org/installer -o "$composer_setup"
    actual_sig=$(php -r "echo hash_file('sha384', '${composer_setup}');")

    if [[ "$expected_sig" != "$actual_sig" ]]; then
        rm -f "$composer_setup"
        log_fatal "Signature Composer invalide — installation annulée"
    fi

    php "$composer_setup" --quiet --install-dir=/usr/local/bin --filename=composer
    rm -f "$composer_setup"
    log_ok "Composer installé"
}

_do_install() {
    _add_ondrej_ppa
    _install_php
    _install_composer
}

installer_run \
    "languages/php" \
    "PHP ${PHP_VERSION} + Composer" \
    "php --version 2>/dev/null | head -1 | awk '{print \$2}'" \
    "_do_install"
