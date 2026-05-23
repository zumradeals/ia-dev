#!/usr/bin/env bash
# bootstrap/10-base-packages.sh — Installation des paquets APT de base
# Idempotent : vérifie chaque paquet avant installation

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="base-packages"

# shellcheck source=../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

require_root
log_init "base-packages" "bootstrap"
log_section "Paquets système de base"

# ── Mise à jour index APT ─────────────────────
log_info "Mise à jour APT..."
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
log_ok "Index APT mis à jour"

# ── Paquets essentiels ────────────────────────
BASE_PACKAGES=(
    # Outils réseau
    curl
    wget
    ca-certificates
    gnupg
    net-tools
    iputils-ping
    dnsutils
    # Développement
    git
    build-essential
    software-properties-common
    pkg-config
    # Archivage
    zip
    unzip
    tar
    gzip
    # Utilitaires système
    jq
    tree
    htop
    ncdu
    lsof
    strace
    # Éditeurs
    vim
    nano
    # Divers
    apt-transport-https
    gnupg2
    lsb-release
    locales
    tzdata
)

log_section "Installation paquets de base"
apt_install "${BASE_PACKAGES[@]}"
log_ok "Tous les paquets de base installés"

# ── Configuration locale ──────────────────────
log_info "Configuration locale système..."
if ! locale | grep -q "LANG=en_US.UTF-8"; then
    locale-gen en_US.UTF-8 > /dev/null 2>&1 || true
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 > /dev/null 2>&1 || true
    log_ok "Locale : en_US.UTF-8"
else
    log_skip "Locale déjà configurée"
fi

# ── Configuration timezone ────────────────────
log_info "Vérification timezone..."
CURRENT_TZ=$(cat /etc/timezone 2>/dev/null || echo "UTC")
if [[ "$CURRENT_TZ" == "UTC" ]]; then
    log_skip "Timezone déjà UTC"
else
    log_info "Timezone actuelle : ${CURRENT_TZ}"
fi

state_set "bootstrap.base-packages" "$(date +%Y%m%d)" "installed"
log_ok "Base packages : terminé"
