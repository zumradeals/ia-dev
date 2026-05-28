#!/usr/bin/env bash
# installers/containers/10-docker.sh — Docker Engine via dépôt officiel
# N'utilise PAS le paquet APT docker.io (obsolète) — utilise docker.com/linux/ubuntu

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="containers/docker"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"
# shellcheck source=../../lib/checks.sh
source "${DEVLAB_ROOT}/lib/checks.sh"

log_init "docker" "install"
log_section "Docker Engine"

DEVLAB_USER="${DEVLAB_USER:-devuser}"
DOCKER_GPG_URL="${DOCKER_GPG_URL:-https://download.docker.com/linux/ubuntu/gpg}"
DOCKER_REPO_URL="${DOCKER_REPO_URL:-https://download.docker.com/linux/ubuntu}"

_add_docker_repo() {
    local keyfile="/etc/apt/keyrings/docker.gpg"
    local listfile="/etc/apt/sources.list.d/docker.list"

    apt_install ca-certificates curl gnupg
    mkdir -p /etc/apt/keyrings

    if [[ ! -f "$keyfile" ]]; then
        log_step "Ajout clé GPG Docker..."
        curl -fsSL "$DOCKER_GPG_URL" | gpg --dearmor -o "$keyfile"
        chmod a+r "$keyfile"
        log_ok "Clé GPG Docker ajoutée"
    else
        log_skip "Clé GPG Docker déjà présente"
    fi

    if [[ ! -f "$listfile" ]]; then
        log_step "Ajout dépôt Docker..."
        # shellcheck source=/dev/null
        source /etc/os-release
        echo "deb [arch=$(dpkg --print-architecture) signed-by=${keyfile}] \
${DOCKER_REPO_URL} ${UBUNTU_CODENAME:-noble} stable" > "$listfile"
        apt_update
        log_ok "Dépôt Docker configuré"
    else
        log_skip "Dépôt Docker déjà configuré"
    fi
}

_install_docker() {
    apt_install \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
}

_configure_docker() {
    # Vérifier que Docker a bien été installé avant de configurer
    command_exists docker || { log_error "Docker non trouvé après installation"; return 1; }

    # Configurer Docker daemon
    local daemon_conf="/etc/docker/daemon.json"
    mkdir -p /etc/docker

    if [[ ! -f "$daemon_conf" ]]; then
        local template="${DEVLAB_ROOT}/configs/docker/daemon.json.tpl"
        if [[ -f "$template" ]]; then
            render_template "$template" "$daemon_conf"
        else
            cat > "$daemon_conf" << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF
        fi
        log_step "Docker daemon.json configuré"
    else
        log_skip "Docker daemon.json déjà présent"
    fi

    # Ajouter devuser au groupe docker
    if check_group_exists docker; then
        if ! id -nG "$DEVLAB_USER" | grep -qw docker; then
            usermod -aG docker "$DEVLAB_USER"
            log_step "${DEVLAB_USER} ajouté au groupe docker"
        else
            log_skip "${DEVLAB_USER} déjà dans le groupe docker"
        fi
    fi

    # Démarrer et activer Docker
    systemctl enable docker --quiet
    systemctl start docker

    log_ok "Docker démarré et activé"
}

_do_install() {
    _add_docker_repo
    _install_docker
    _configure_docker
}

installer_run \
    "containers/docker" \
    "Docker Engine" \
    "docker --version 2>/dev/null | awk '{print \$3}' | tr -d ','" \
    "_do_install"

# Test de sanité (non bloquant)
if command_exists docker && docker info &>/dev/null; then
    log_ok "Docker opérationnel"
else
    log_warn "Docker installé mais daemon non accessible — reconnectez-vous ou : newgrp docker"
fi
