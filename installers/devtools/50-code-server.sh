#!/usr/bin/env bash
# installers/devtools/50-code-server.sh — VS Code Server (code-server)
# Accès VS Code complet dans le navigateur sur http://VPS_IP:8080

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="devtools/code-server"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "code-server" "install"
log_section "code-server (VS Code in browser)"

DEVLAB_USER="${DEVLAB_USER:-root}"
USER_HOME=$(getent passwd "$DEVLAB_USER" | cut -d: -f6)
CODE_SERVER_PORT="${CODE_SERVER_PORT:-8080}"
CODE_SERVER_AUTH="${CODE_SERVER_AUTH:-password}"
CODE_SERVER_CONFIG="${USER_HOME}/.config/code-server/config.yaml"
SERVICE_NAME="code-server@${DEVLAB_USER}"

_install_binary() {
    if command_exists code-server; then
        log_skip "code-server binaire déjà présent ($(code-server --version 2>/dev/null | head -1))"
        return 0
    fi
    log_step "Téléchargement code-server..."
    curl -fsSL https://code-server.dev/install.sh | \
        sh -s -- --method=standalone --prefix="${USER_HOME}/.local" 2>/dev/null
    log_ok "code-server installé"
}

_configure() {
    local config_dir
    config_dir=$(dirname "$CODE_SERVER_CONFIG")
    mkdir -p "$config_dir"

    if [[ -f "$CODE_SERVER_CONFIG" ]]; then
        log_skip "code-server config déjà présente : ${CODE_SERVER_CONFIG}"
        return 0
    fi

    local password
    password=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 20)

    cat > "$CODE_SERVER_CONFIG" << EOF
bind-addr: 0.0.0.0:${CODE_SERVER_PORT}
auth: ${CODE_SERVER_AUTH}
password: ${password}
cert: false
disable-telemetry: true
EOF
    chmod 600 "$CODE_SERVER_CONFIG"

    log_ok "code-server configuré — port ${CODE_SERVER_PORT}"
    log_warn "Mot de passe : ${password}"
    log_warn "Conservé dans : ${CODE_SERVER_CONFIG}"
}

_setup_systemd() {
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

    if [[ -f "$service_file" ]]; then
        log_skip "Service systemd déjà présent"
    else
        local bin
        bin=$(command -v code-server 2>/dev/null || echo "${USER_HOME}/.local/bin/code-server")

        cat > "$service_file" << EOF
[Unit]
Description=code-server — VS Code in browser
After=network.target

[Service]
Type=simple
User=${DEVLAB_USER}
WorkingDirectory=${DEVLAB_ROOT}/workspace
ExecStart=${bin} --config ${CODE_SERVER_CONFIG} ${DEVLAB_ROOT}/workspace
Restart=on-failure
RestartSec=5
Environment=HOME=${USER_HOME}
Environment=PATH=${USER_HOME}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable "$SERVICE_NAME" --quiet
        log_ok "Service systemd ${SERVICE_NAME} créé et activé"
    fi

    # Démarrer ou redémarrer
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl restart "$SERVICE_NAME"
        log_ok "code-server redémarré"
    else
        systemctl start "$SERVICE_NAME"
        log_ok "code-server démarré"
    fi
}

_configure_nginx_proxy() {
    local domain="${GAMADCODE_DOMAIN:-}"
    [[ -z "$domain" ]] && return 0
    command_exists nginx || return 0

    local conf="/etc/nginx/conf.d/code-server.conf"
    [[ -f "$conf" ]] && { log_skip "Nginx code-server déjà configuré"; return 0; }

    cat > "$conf" << EOF
server {
    listen 80;
    server_name ${domain};

    location / {
        proxy_pass http://127.0.0.1:${CODE_SERVER_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 3600s;
        proxy_buffering off;
    }
}
EOF
    nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
    log_ok "Nginx proxy code-server → ${domain} → :${CODE_SERVER_PORT}"
}

_do_install() {
    _install_binary
    _configure
    _setup_systemd
    _configure_nginx_proxy
}

installer_run \
    "devtools/code-server" \
    "code-server" \
    "code-server --version 2>/dev/null | head -1" \
    "_do_install"

# Afficher les infos de connexion même si déjà installé
echo
log_section "Accès VS Code"
local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
stored_password=$(grep '^password:' "$CODE_SERVER_CONFIG" 2>/dev/null | awk '{print $2}' || echo "(voir ${CODE_SERVER_CONFIG})")
echo
printf "  URL       : http://%s:%s\n" "${local_ip:-VOTRE_IP}" "${CODE_SERVER_PORT}"
printf "  Mot de passe : %s\n" "${stored_password}"
echo
log_info "Statut : systemctl status ${SERVICE_NAME}"
log_info "Logs   : journalctl -u ${SERVICE_NAME} -f"
