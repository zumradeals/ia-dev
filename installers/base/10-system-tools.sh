#!/usr/bin/env bash
# installers/base/10-system-tools.sh — Outils CLI système avancés
# Idempotent — vérifie chaque outil avant installation

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="base/system-tools"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"
# shellcheck source=../../lib/checks.sh
source "${DEVLAB_ROOT}/lib/checks.sh"

log_init "system-tools" "install"
log_section "Outils système"

_do_install() {
    apt_install \
        htop \
        iotop \
        ncdu \
        tree \
        jq \
        yq \
        tmux \
        screen \
        net-tools \
        iputils-ping \
        dnsutils \
        nmap \
        lsof \
        strace \
        pv \
        moreutils \
        parallel \
        rsync \
        openssh-server \
        ufw \
        fail2ban
}

installer_run \
    "base/system-tools" \
    "System Tools" \
    "echo bundle-$(date +%Y%m%d)" \
    "_do_install"

# ── openssh-server : activer et démarrer ─────
if check_apt_package "openssh-server"; then
    if ! check_service_running "ssh" && ! check_service_running "sshd"; then
        systemctl enable ssh --quiet 2>/dev/null || systemctl enable sshd --quiet 2>/dev/null || true
        systemctl start ssh 2>/dev/null || systemctl start sshd 2>/dev/null || true
        log_ok "SSH démarré"
    else
        log_skip "SSH déjà actif"
    fi
fi
