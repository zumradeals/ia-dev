#!/usr/bin/env bash
# bootstrap/20-security.sh — Configuration sécurité : UFW, Fail2ban, SSH hardening
# Idempotent : chaque opération vérifie l'état actuel

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="security"

# shellcheck source=../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"
# shellcheck source=../lib/security.sh
source "${DEVLAB_ROOT}/lib/security.sh"

require_root
log_init "security" "bootstrap"
log_section "Configuration sécurité système"

# ── UFW ───────────────────────────────────────
log_section "Pare-feu UFW"
apt_install ufw

if ufw status | grep -q "Status: active"; then
    log_skip "UFW déjà actif"
else
    ufw --force reset > /dev/null 2>&1
    ufw default deny incoming > /dev/null
    ufw default allow outgoing > /dev/null
    log_ok "UFW : politique par défaut configurée (deny in / allow out)"
fi

# Ports depuis la config
declare -a ports_to_allow
IFS=' ' read -ra ports_to_allow <<< "${UFW_ALLOW_PORTS:-22 80 443}"

for port in "${ports_to_allow[@]}"; do
    ufw_allow_port "$port"
done

ufw --force enable > /dev/null
log_ok "UFW activé"

# ── FAIL2BAN ─────────────────────────────────
log_section "Fail2ban"
configure_fail2ban

# ── SSH HARDENING ─────────────────────────────
log_section "Durcissement SSH"

SSHD_CONFIG="/etc/ssh/sshd_config"
backup_file "$SSHD_CONFIG"

# Paramètres de durcissement
declare -A SSH_PARAMS=(
    ["PermitRootLogin"]="${SSH_PERMIT_ROOT:-no}"
    ["PasswordAuthentication"]="${SSH_PASSWORD_AUTH:-no}"
    ["MaxAuthTries"]="${SSH_MAX_AUTH_TRIES:-3}"
    ["X11Forwarding"]="no"
    ["PermitEmptyPasswords"]="no"
    ["Protocol"]="2"
    ["LoginGraceTime"]="30"
    ["ClientAliveInterval"]="300"
    ["ClientAliveCountMax"]="2"
)

for param in "${!SSH_PARAMS[@]}"; do
    value="${SSH_PARAMS[$param]}"
    if grep -qE "^${param}\s" "$SSHD_CONFIG"; then
        sed -i "s|^${param}\s.*|${param} ${value}|" "$SSHD_CONFIG"
    elif grep -qE "^#${param}\s" "$SSHD_CONFIG"; then
        sed -i "s|^#${param}\s.*|${param} ${value}|" "$SSHD_CONFIG"
    else
        echo "${param} ${value}" >> "$SSHD_CONFIG"
    fi
    log_step "${param} = ${value}"
done

# Validation syntaxe avant rechargement
if sshd -t 2>/dev/null; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
    log_ok "SSH rechargé avec la nouvelle configuration"
else
    log_warn "Validation SSH échouée — configuration inchangée (backup disponible)"
fi

# ── RÉSUMÉ ───────────────────────────────────
state_set "bootstrap.security" "$(date +%Y%m%d)" "installed"
log_ok "Configuration sécurité terminée"
echo
log_warn "ATTENTION : PasswordAuthentication=no — assurez-vous d'avoir une clé SSH configurée !"
log_info "Pour autoriser l'accès par clé : cat ~/.ssh/id_rsa.pub >> /home/${DEVLAB_USER:-devuser}/.ssh/authorized_keys"
