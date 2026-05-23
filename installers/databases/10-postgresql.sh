#!/usr/bin/env bash
# installers/databases/10-postgresql.sh — PostgreSQL via dépôt officiel PGDG
# N'utilise PAS le paquet APT Ubuntu (version ancienne) — utilise postgresql.org

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="databases/postgresql"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"
# shellcheck source=../../lib/checks.sh
source "${DEVLAB_ROOT}/lib/checks.sh"

log_init "postgresql" "install"
log_section "PostgreSQL ${POSTGRES_VERSION:-16}"

PG_VERSION="${POSTGRES_VERSION:-16}"
PG_PORT="${POSTGRES_PORT:-5432}"
DEVLAB_USER="${DEVLAB_USER:-devuser}"

_add_pgdg_repo() {
    local keyfile="/etc/apt/keyrings/postgresql.gpg"
    local listfile="/etc/apt/sources.list.d/postgresql.list"

    apt_install curl gnupg
    mkdir -p /etc/apt/keyrings

    if [[ ! -f "$keyfile" ]]; then
        log_step "Ajout clé GPG PostgreSQL..."
        curl -fsSL "https://www.postgresql.org/media/keys/ACCC4CF8.asc" | \
            gpg --dearmor -o "$keyfile"
        chmod a+r "$keyfile"
        log_ok "Clé GPG PostgreSQL ajoutée"
    else
        log_skip "Clé GPG déjà présente"
    fi

    if [[ ! -f "$listfile" ]]; then
        log_step "Ajout dépôt PGDG..."
        # shellcheck source=/dev/null
        source /etc/os-release
        echo "deb [signed-by=${keyfile}] https://apt.postgresql.org/pub/repos/apt \
${VERSION_CODENAME}-pgdg main" > "$listfile"
        apt_update
        log_ok "Dépôt PGDG configuré"
    else
        log_skip "Dépôt PGDG déjà configuré"
    fi
}

_install_postgresql() {
    apt_install \
        "postgresql-${PG_VERSION}" \
        "postgresql-client-${PG_VERSION}" \
        "postgresql-${PG_VERSION}-pgvector" \
        libpq-dev
}

_configure_postgresql() {
    local pg_conf_dir="/etc/postgresql/${PG_VERSION}/main"
    local pg_hba="${pg_conf_dir}/pg_hba.conf"

    # Démarrer PostgreSQL
    systemctl enable "postgresql@${PG_VERSION}-main" --quiet 2>/dev/null || \
        systemctl enable postgresql --quiet 2>/dev/null || true
    systemctl start "postgresql@${PG_VERSION}-main" 2>/dev/null || \
        systemctl start postgresql 2>/dev/null || true

    # Attendre que PostgreSQL soit prêt
    local retries=10
    while [[ $retries -gt 0 ]]; do
        if pg_isready -q 2>/dev/null; then
            break
        fi
        sleep 1
        (( retries-- )) || true
    done

    # Créer l'utilisateur devuser dans PostgreSQL (idempotent)
    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DEVLAB_USER}'" 2>/dev/null | grep -q 1; then
        sudo -u postgres psql -c "CREATE USER ${DEVLAB_USER} WITH SUPERUSER CREATEDB CREATEROLE;" 2>/dev/null
        log_ok "Utilisateur PostgreSQL '${DEVLAB_USER}' créé"
    else
        log_skip "Utilisateur PostgreSQL '${DEVLAB_USER}' déjà existant"
    fi

    # Créer base de données devlab
    if ! sudo -u postgres psql -lqt 2>/dev/null | cut -d\| -f1 | grep -qw "devlab"; then
        sudo -u postgres createdb -O "$DEVLAB_USER" devlab 2>/dev/null
        log_ok "Base 'devlab' créée"
    else
        log_skip "Base 'devlab' déjà existante"
    fi

    log_ok "PostgreSQL configuré sur port ${PG_PORT}"
}

_do_install() {
    _add_pgdg_repo
    _install_postgresql
    _configure_postgresql
}

installer_run \
    "databases/postgresql" \
    "PostgreSQL ${PG_VERSION}" \
    "psql --version 2>/dev/null | awk '{print \$3}'" \
    "_do_install"
