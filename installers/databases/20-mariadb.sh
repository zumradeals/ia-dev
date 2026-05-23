#!/usr/bin/env bash
# installers/databases/20-mariadb.sh — MariaDB via dépôt officiel mariadb.org

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="databases/mariadb"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "mariadb" "install"
log_section "MariaDB ${MARIADB_VERSION:-10.11}"

MARIADB_VERSION="${MARIADB_VERSION:-10.11}"
DEVLAB_USER="${DEVLAB_USER:-devuser}"

_add_mariadb_repo() {
    local keyfile="/etc/apt/keyrings/mariadb.gpg"
    local listfile="/etc/apt/sources.list.d/mariadb.list"

    if [[ -f "$listfile" ]]; then
        log_skip "Dépôt MariaDB déjà configuré"
        return 0
    fi

    apt_install curl gnupg
    mkdir -p /etc/apt/keyrings

    curl -fsSL "https://downloads.mariadb.com/MariaDB/mariadb_repo_setup" | \
        bash -s -- --mariadb-server-version="mariadb-${MARIADB_VERSION}" > /dev/null 2>&1
    log_ok "Dépôt MariaDB ${MARIADB_VERSION} configuré"
}

_install_mariadb() {
    apt_install mariadb-server mariadb-client libmariadb-dev
}

_configure_mariadb() {
    systemctl enable mariadb --quiet
    systemctl start mariadb

    # Sécurisation basique (non-interactive)
    local retries=10
    while [[ $retries -gt 0 ]]; do
        if mysqladmin ping --silent 2>/dev/null; then
            break
        fi
        sleep 1
        (( retries-- )) || true
    done

    # Créer utilisateur devuser
    if ! mysql -u root -e "SELECT User FROM mysql.user WHERE User='${DEVLAB_USER}'" 2>/dev/null | grep -q "$DEVLAB_USER"; then
        mysql -u root << SQL 2>/dev/null
CREATE USER IF NOT EXISTS '${DEVLAB_USER}'@'localhost' IDENTIFIED BY '';
GRANT ALL PRIVILEGES ON *.* TO '${DEVLAB_USER}'@'localhost' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS devlab;
FLUSH PRIVILEGES;
SQL
        log_ok "Utilisateur MariaDB '${DEVLAB_USER}' créé"
    else
        log_skip "Utilisateur MariaDB '${DEVLAB_USER}' déjà existant"
    fi
}

_do_install() {
    _add_mariadb_repo
    _install_mariadb
    _configure_mariadb
}

installer_run \
    "databases/mariadb" \
    "MariaDB ${MARIADB_VERSION}" \
    "mysql --version 2>/dev/null | awk '{print \$5}' | tr -d ','" \
    "_do_install"
