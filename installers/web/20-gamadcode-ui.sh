#!/usr/bin/env bash
# installers/web/20-gamadcode-ui.sh — GamadCode Web UI (Express + WebSocket)

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="web/gamadcode-ui"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "gamadcode-ui" "install"
log_section "GamadCode Web UI"

_install_deps() {
    command_exists node || { log_error "Node.js requis — installez d'abord languages/nodejs"; return 1; }
    local node_ver; node_ver=$(node --version)
    log_step "Node.js ${node_ver}"

    local web_dir="${DEVLAB_ROOT}/web"
    if [[ ! -d "${web_dir}/node_modules" ]]; then
        log_step "Installation des dépendances npm…"
        cd "$web_dir"
        npm install --omit=dev --silent
        log_ok "Dépendances npm installées"
    else
        log_skip "node_modules déjà présent"
    fi
}

_configure_service() {
    local service_file="/etc/systemd/system/gamadcode-ui.service"
    local web_dir="${DEVLAB_ROOT}/web"
    local ui_port="${GAMADCODE_UI_PORT:-3000}"

    if [[ -f "$service_file" ]]; then
        log_skip "Service gamadcode-ui déjà configuré"
        return 0
    fi

    cat > "$service_file" << EOF
[Unit]
Description=GamadCode Web UI
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/bin/node ${web_dir}/server.js
WorkingDirectory=${web_dir}
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production
Environment=GAMADCODE_UI_PORT=${ui_port}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable gamadcode-ui --quiet
    log_ok "Service gamadcode-ui configuré (port ${ui_port})"
}

_configure_nginx() {
    local domain="${GAMADCODE_DOMAIN:-}"
    local ui_port="${GAMADCODE_UI_PORT:-3000}"
    local conf_file="/etc/nginx/conf.d/gamadcode-ui.conf"

    if [[ -f "$conf_file" ]]; then
        log_skip "Nginx gamadcode-ui déjà configuré"
        return 0
    fi

    if ! command_exists nginx; then
        log_warn "Nginx non installé — proxy non configuré"
        return 0
    fi

    if [[ -n "$domain" ]]; then
        cat > "$conf_file" << EOF
server {
    listen 80;
    server_name ${domain};

    location / {
        proxy_pass http://127.0.0.1:${ui_port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 3600s;
    }
}
EOF
        log_ok "Nginx proxy → ${domain} → :${ui_port}"
    else
        log_skip "GAMADCODE_DOMAIN non défini — proxy Nginx ignoré"
        log_info "Pour configurer un domaine, ajoutez GAMADCODE_DOMAIN=votre-domaine dans config/local.env"
    fi
}

_start_service() {
    if systemctl is-active --quiet gamadcode-ui 2>/dev/null; then
        systemctl restart gamadcode-ui
        log_ok "GamadCode UI redémarré"
    else
        systemctl start gamadcode-ui 2>/dev/null || true
        sleep 1
        if systemctl is-active --quiet gamadcode-ui 2>/dev/null; then
            log_ok "GamadCode UI démarré"
        else
            log_warn "GamadCode UI n'a pas démarré — vérifiez : journalctl -u gamadcode-ui"
        fi
    fi

    local ip; ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    local ui_port="${GAMADCODE_UI_PORT:-3000}"
    log_info "Interface disponible sur : http://${ip}:${ui_port}"
    if [[ -n "${GAMADCODE_DOMAIN:-}" ]]; then
        log_info "Via domaine : http://${GAMADCODE_DOMAIN}"
    fi
}

_do_install() {
    _install_deps
    _configure_service
    _configure_nginx
    _start_service
}

installer_run \
    "web/gamadcode-ui" \
    "GamadCode UI" \
    "systemctl is-active gamadcode-ui 2>/dev/null || echo 'stopped'" \
    "_do_install"
