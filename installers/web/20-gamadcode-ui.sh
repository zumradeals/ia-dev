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

# ── Résoudre node/npm depuis nvm ou PATH ─────────────────────────────────────
_resolve_node() {
    # Source nvm si disponible (nvm installe node hors du PATH système)
    local nvm_script="${HOME}/.nvm/nvm.sh"
    if [[ -s "$nvm_script" ]]; then
        # shellcheck source=/dev/null
        source "$nvm_script"
    fi

    NODE_BIN="$(command -v node 2>/dev/null || true)"
    NPM_BIN="$(command -v npm  2>/dev/null || true)"

    if [[ -z "$NODE_BIN" ]]; then
        log_error "Node.js introuvable — installez d'abord languages/nodejs"
        return 1
    fi
    if [[ -z "$NPM_BIN" ]]; then
        log_error "npm introuvable — vérifiez l'installation de Node.js"
        return 1
    fi

    log_step "Node.js : $("$NODE_BIN" --version)  |  npm : $("$NPM_BIN" --version)"
}

_install_deps() {
    _resolve_node

    local web_dir="${DEVLAB_ROOT}/web"
    if [[ ! -d "${web_dir}/node_modules" ]]; then
        log_step "Installation des dépendances npm…"
        cd "$web_dir"
        "$NPM_BIN" install --omit=dev --silent
        log_ok "Dépendances npm installées"
    else
        log_skip "node_modules déjà présent"
    fi
}

_create_wrapper() {
    local wrapper="/usr/local/bin/gamadcode-start"
    local web_dir="${DEVLAB_ROOT}/web"

    cat > "$wrapper" << WRAPPER
#!/bin/bash
# Wrapper GamadCode UI — charge nvm puis démarre node
[ -s "\${HOME}/.nvm/nvm.sh" ] && source "\${HOME}/.nvm/nvm.sh"
exec node ${web_dir}/server.js
WRAPPER
    chmod +x "$wrapper"
    log_step "Wrapper créé : ${wrapper}"
}

_configure_service() {
    local service_file="/etc/systemd/system/gamadcode-ui.service"
    local web_dir="${DEVLAB_ROOT}/web"
    local ui_port="${GAMADCODE_UI_PORT:-3000}"

    # Recréer si le ExecStart pointe encore sur /usr/bin/node (ancienne version)
    if [[ -f "$service_file" ]] && grep -q "ExecStart=/usr/bin/node" "$service_file"; then
        log_step "Mise à jour du service (ancien ExecStart corrigé)…"
        rm -f "$service_file"
    fi

    if [[ -f "$service_file" ]]; then
        log_skip "Service gamadcode-ui déjà configuré"
        return 0
    fi

    _create_wrapper

    cat > "$service_file" << EOF
[Unit]
Description=GamadCode Web UI
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gamadcode-start
WorkingDirectory=${web_dir}
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production
Environment=GAMADCODE_UI_PORT=${ui_port}
Environment=HOME=/root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable gamadcode-ui --quiet
    log_ok "Service gamadcode-ui configuré (port ${ui_port})"
}

_configure_nginx() {
    # GAMADCODE_UI_DOMAIN → domaine dédié au dashboard (ex: app.gamad.net)
    # Fallback sur GAMADCODE_DOMAIN si UI_DOMAIN non défini
    local domain="${GAMADCODE_UI_DOMAIN:-${GAMADCODE_DOMAIN:-}}"
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
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 3600s;
    }
}
EOF
        log_ok "Nginx proxy → ${domain} → :${ui_port}"
    else
        log_skip "GAMADCODE_DOMAIN non défini — proxy Nginx ignoré"
        log_info "Pour un domaine, ajoutez GAMADCODE_DOMAIN=votre-domaine dans config/local.env"
    fi
}

_start_service() {
    if systemctl is-active --quiet gamadcode-ui 2>/dev/null; then
        systemctl restart gamadcode-ui
        log_ok "GamadCode UI redémarré"
    else
        systemctl start gamadcode-ui 2>/dev/null || true
        sleep 2
        if systemctl is-active --quiet gamadcode-ui 2>/dev/null; then
            log_ok "GamadCode UI démarré"
        else
            log_warn "Démarrage différé — vérifiez : journalctl -u gamadcode-ui -n 30"
        fi
    fi

    local ip; ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    local ui_port="${GAMADCODE_UI_PORT:-3000}"
    log_info "Interface disponible sur : http://${ip}:${ui_port}"
    if [[ -n "${GAMADCODE_DOMAIN:-}" ]]; then
        log_info "Via domaine : http://${GAMADCODE_DOMAIN}"
    fi
    log_info "Wizard de configuration : http://${ip}:${ui_port}/setup"
}

_setup_database() {
    local pg_user="${POSTGRES_USER:-gamadcode}"
    local pg_pass="${POSTGRES_PASSWORD:-}"
    local pg_db="${POSTGRES_DB:-gamadcode}"

    if ! command -v psql &>/dev/null; then
        log_warn "psql non disponible — DB skip"
        return 0
    fi

    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${pg_user}'" 2>/dev/null | grep -q 1; then
        log_step "Création utilisateur PostgreSQL '${pg_user}'…"
        sudo -u postgres psql -c "CREATE USER ${pg_user} WITH PASSWORD '${pg_pass}';" 2>/dev/null
        log_ok "Utilisateur '${pg_user}' créé"
    else
        sudo -u postgres psql -c "ALTER USER ${pg_user} WITH PASSWORD '${pg_pass}';" 2>/dev/null || true
        log_skip "Utilisateur '${pg_user}' déjà existant"
    fi

    if ! sudo -u postgres psql -lqt 2>/dev/null | cut -d\| -f1 | grep -qw "${pg_db}"; then
        log_step "Création base '${pg_db}'…"
        sudo -u postgres createdb -O "${pg_user}" "${pg_db}" 2>/dev/null
        sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${pg_db} TO ${pg_user};" 2>/dev/null
        log_ok "Base '${pg_db}' créée"
    else
        log_skip "Base '${pg_db}' déjà existante"
    fi

    local nvm_script="${HOME}/.nvm/nvm.sh"
    [[ -s "$nvm_script" ]] && source "$nvm_script"
    if command -v node &>/dev/null; then
        log_step "Migration de la base de données…"
        node "${DEVLAB_ROOT}/web/scripts/migrate.js" 2>/dev/null && log_ok "Migration appliquée" || log_warn "Migration échouée — vérifiez les logs"
    fi
}

_do_install() {
    _install_deps
    _setup_database
    _configure_service
    _configure_nginx
    _start_service
}

installer_run \
    "web/gamadcode-ui" \
    "GamadCode UI" \
    "systemctl is-active gamadcode-ui 2>/dev/null || echo 'stopped'" \
    "_do_install"
