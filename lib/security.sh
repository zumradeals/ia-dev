#!/usr/bin/env bash
# lib/security.sh — Fonctions de sécurité système
# Requiert lib/core.sh déjà sourcé

# ─────────────────────────────────────────────
# UFW — PARE-FEU
# ─────────────────────────────────────────────
ufw_allow_port() {
    local port="$1"
    local proto="${2:-tcp}"

    if ufw status | grep -qE "^${port}/${proto}\s+ALLOW"; then
        log_skip "UFW : port ${port}/${proto} déjà autorisé"
        return 0
    fi

    ufw allow "${port}/${proto}" > /dev/null
    log_ok "UFW : port ${port}/${proto} autorisé"
}

ufw_allow_service() {
    local service="$1"
    if ufw status | grep -qE "^${service}\s+ALLOW"; then
        log_skip "UFW : service ${service} déjà autorisé"
        return 0
    fi
    ufw allow "$service" > /dev/null
    log_ok "UFW : service ${service} autorisé"
}

configure_ufw() {
    log_section "Configuration UFW"
    require_root

    if ! command_exists ufw; then
        apt_install ufw
    fi

    # Politique par défaut : tout refuser en entrée
    ufw --force reset > /dev/null 2>&1
    ufw default deny incoming > /dev/null
    ufw default allow outgoing > /dev/null

    # Ouvertures depuis la config
    local ports="${UFW_ALLOW_PORTS:-22 80 443}"
    for port in $ports; do
        ufw_allow_port "$port"
    done

    # Activation
    ufw --force enable > /dev/null
    log_ok "UFW activé"
    ufw status numbered
}

# ─────────────────────────────────────────────
# SSH HARDENING
# ─────────────────────────────────────────────
harden_ssh() {
    log_section "Durcissement SSH"
    require_root

    local sshd_config="/etc/ssh/sshd_config"
    local template="${DEVLAB_ROOT}/configs/ssh/sshd_config.tpl"

    backup_file "$sshd_config"

    if [[ -f "$template" ]]; then
        render_template "$template" "$sshd_config"
    else
        # Hardening minimal inline si template absent
        _apply_ssh_hardening_inline "$sshd_config"
    fi

    sshd -t 2>/dev/null || log_fatal "Configuration SSH invalide — backup restauré"
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null
    log_ok "SSH durci et rechargé"
}

_apply_ssh_hardening_inline() {
    local conf="$1"

    declare -A ssh_params=(
        ["Port"]="${SSH_PORT:-22}"
        ["PermitRootLogin"]="${SSH_PERMIT_ROOT:-no}"
        ["PasswordAuthentication"]="${SSH_PASSWORD_AUTH:-no}"
        ["MaxAuthTries"]="${SSH_MAX_AUTH_TRIES:-3}"
        ["X11Forwarding"]="no"
        ["AllowAgentForwarding"]="no"
        ["PermitEmptyPasswords"]="no"
        ["Protocol"]="2"
        ["LoginGraceTime"]="30"
    )

    for param in "${!ssh_params[@]}"; do
        local value="${ssh_params[$param]}"
        if grep -qE "^#?${param}\s" "$conf"; then
            sed -i "s|^#\?${param}\s.*|${param} ${value}|" "$conf"
        else
            echo "${param} ${value}" >> "$conf"
        fi
    done
}

# ─────────────────────────────────────────────
# FAIL2BAN
# ─────────────────────────────────────────────
configure_fail2ban() {
    log_section "Configuration Fail2ban"
    require_root

    apt_install fail2ban

    local jail_local="/etc/fail2ban/jail.local"

    if [[ -f "$jail_local" ]]; then
        log_skip "Fail2ban jail.local déjà configuré"
        return 0
    fi

    cat > "$jail_local" << EOF
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ${SSH_PORT:-22}
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 86400
EOF

    systemctl enable fail2ban --quiet
    systemctl restart fail2ban
    log_ok "Fail2ban configuré et démarré"
}

# ─────────────────────────────────────────────
# PERMISSIONS FICHIERS SENSIBLES
# ─────────────────────────────────────────────
secure_secrets_dir() {
    local secrets_file="${DEVLAB_ROOT}/config/secrets.env"

    if [[ -f "$secrets_file" ]]; then
        chmod 600 "$secrets_file"
        log_ok "Permissions sécurisées sur secrets.env"
    fi

    chmod 700 "${DEVLAB_ROOT}/config" 2>/dev/null || true
}

check_secrets_not_in_git() {
    local secrets_file="${DEVLAB_ROOT}/config/secrets.env"
    if git -C "${DEVLAB_ROOT}" ls-files --error-unmatch "$secrets_file" &>/dev/null; then
        log_fatal "DANGER : secrets.env est tracké par Git ! Retirez-le immédiatement avec git rm --cached"
    fi
}
