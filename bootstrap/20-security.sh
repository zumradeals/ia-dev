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

# Vérifier qu'une clé SSH est disponible avant de désactiver le mot de passe
_ssh_key_exists() {
    local user="${DEVLAB_USER:-devuser}"
    local root_keys="/root/.ssh/authorized_keys"
    local user_keys
    user_keys="$(getent passwd "$user" | cut -d: -f6)/.ssh/authorized_keys"

    [[ -s "$root_keys" ]] || [[ -s "$user_keys" ]]
}

# Paramètres toujours appliqués (sans risque de lockout)
declare -A SSH_SAFE_PARAMS=(
    ["MaxAuthTries"]="${SSH_MAX_AUTH_TRIES:-3}"
    ["X11Forwarding"]="no"
    ["PermitEmptyPasswords"]="no"
    ["Protocol"]="2"
    ["LoginGraceTime"]="30"
    ["ClientAliveInterval"]="300"
    ["ClientAliveCountMax"]="2"
)

for param in "${!SSH_SAFE_PARAMS[@]}"; do
    value="${SSH_SAFE_PARAMS[$param]}"
    if grep -qE "^${param}\s" "$SSHD_CONFIG"; then
        sed -i "s|^${param}\s.*|${param} ${value}|" "$SSHD_CONFIG"
    elif grep -qE "^#${param}\s" "$SSHD_CONFIG"; then
        sed -i "s|^#${param}\s.*|${param} ${value}|" "$SSHD_CONFIG"
    else
        echo "${param} ${value}" >> "$SSHD_CONFIG"
    fi
    log_step "${param} = ${value}"
done

# PermitRootLogin : appliqué seulement si SSH_PERMIT_ROOT est explicitement "no"
if [[ "${SSH_PERMIT_ROOT:-}" == "no" ]]; then
    sed -i "s|^#\?PermitRootLogin\s.*|PermitRootLogin no|" "$SSHD_CONFIG"
    log_step "PermitRootLogin = no"
else
    log_skip "PermitRootLogin conservé (SSH_PERMIT_ROOT non forcé à 'no')"
fi

# PasswordAuthentication : seulement si une clé SSH est déjà présente
if [[ "${SSH_PASSWORD_AUTH:-}" == "no" ]]; then
    if _ssh_key_exists; then
        sed -i "s|^#\?PasswordAuthentication\s.*|PasswordAuthentication no|" "$SSHD_CONFIG"
        log_ok "PasswordAuthentication = no (clé SSH détectée)"
    else
        log_warn "PasswordAuthentication NON désactivé — aucune clé SSH trouvée dans authorized_keys"
        log_warn "Ajoutez d'abord votre clé SSH, puis relancez : devlab reset bootstrap.security && sudo devlab bootstrap"
    fi
else
    log_skip "PasswordAuthentication conservé (SSH_PASSWORD_AUTH non forcé à 'no')"
fi

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
log_info "Pour durcir SSH (désactiver le mot de passe), configurez dans config/local.env :"
log_info "  SSH_PASSWORD_AUTH=no  # requiert une clé dans ~/.ssh/authorized_keys"
log_info "  SSH_PERMIT_ROOT=no    # recommandé si vous utilisez devuser"
