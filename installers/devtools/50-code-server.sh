#!/usr/bin/env bash
# installers/devtools/50-code-server.sh — VS Code Server (code-server)
# Accès VS Code dans le navigateur — lourd (~350MB), désactivé par défaut

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

DEVLAB_USER="${DEVLAB_USER:-devuser}"
USER_HOME=$(getent passwd "$DEVLAB_USER" | cut -d: -f6)
CODE_SERVER_PORT="${CODE_SERVER_PORT:-8080}"
CODE_SERVER_AUTH="${CODE_SERVER_AUTH:-password}"

_do_install() {
    if command_exists code-server; then
        log_skip "code-server déjà installé ($(code-server --version 2>/dev/null | head -1))"
        return 0
    fi

    log_step "Téléchargement et installation code-server..."
    curl -fsSL https://code-server.dev/install.sh | \
        sh -s -- --method=standalone --prefix="${USER_HOME}/.local" 2>/dev/null

    chown -R "${DEVLAB_USER}:$(id -gn "$DEVLAB_USER")" "${USER_HOME}/.local" 2>/dev/null || true
    log_ok "code-server installé"
}

_configure_code_server() {
    local config_dir="${USER_HOME}/.config/code-server"
    local config_file="${config_dir}/config.yaml"

    if [[ -f "$config_file" ]]; then
        log_skip "code-server config déjà présente"
        return 0
    fi

    mkdir -p "$config_dir"
    chown "${DEVLAB_USER}:$(id -gn "$DEVLAB_USER")" "$config_dir"

    # Générer un mot de passe aléatoire si auth=password
    local password
    password=$(openssl rand -base64 16 2>/dev/null || dd if=/dev/urandom bs=16 count=1 2>/dev/null | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)

    cat > "$config_file" << EOF
bind-addr: 0.0.0.0:${CODE_SERVER_PORT}
auth: ${CODE_SERVER_AUTH}
password: ${password}
cert: false
EOF
    chown "${DEVLAB_USER}:$(id -gn "$DEVLAB_USER")" "$config_file"
    chmod 600 "$config_file"

    log_ok "code-server configuré sur port ${CODE_SERVER_PORT}"
    log_warn "Mot de passe généré : ${password}"
    log_warn "Stocké dans : ${config_file} (chmod 600)"
}

_create_systemd_service() {
    local service_file="/etc/systemd/system/code-server@${DEVLAB_USER}.service"

    if [[ -f "$service_file" ]]; then
        log_skip "Service systemd code-server déjà présent"
        return 0
    fi

    local code_server_bin="${USER_HOME}/.local/bin/code-server"
    [[ ! -f "$code_server_bin" ]] && code_server_bin="$(which code-server 2>/dev/null || echo code-server)"

    cat > "$service_file" << EOF
[Unit]
Description=code-server
After=network.target

[Service]
Type=simple
User=${DEVLAB_USER}
WorkingDirectory=${USER_HOME}
ExecStart=${code_server_bin} --config ${USER_HOME}/.config/code-server/config.yaml ${DEVLAB_ROOT}/workspace
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "code-server@${DEVLAB_USER}" --quiet
    log_ok "Service systemd code-server créé"
    log_info "Démarrer : systemctl start code-server@${DEVLAB_USER}"
}

installer_run \
    "devtools/code-server" \
    "code-server" \
    "code-server --version 2>/dev/null | head -1" \
    "_do_install"

_configure_code_server
_create_systemd_service

echo
log_info "Accès : http://VOTRE_IP:${CODE_SERVER_PORT}"
log_info "Démarrer le service : systemctl start code-server@${DEVLAB_USER}"
