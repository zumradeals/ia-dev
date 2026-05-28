#!/usr/bin/env bash
# installers/web/10-nginx.sh — Nginx via dépôt officiel nginx.org

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="web/nginx"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "nginx" "install"
log_section "Nginx"

_add_nginx_repo() {
    local keyfile="/etc/apt/keyrings/nginx.gpg"
    local listfile="/etc/apt/sources.list.d/nginx.list"

    if [[ -f "$listfile" ]]; then
        log_skip "Dépôt Nginx déjà configuré"
        return 0
    fi

    apt_install curl gnupg
    mkdir -p /etc/apt/keyrings

    curl -fsSL "https://nginx.org/keys/nginx_signing.key" | \
        gpg --dearmor -o "$keyfile"
    chmod a+r "$keyfile"

    # shellcheck source=/dev/null
    source /etc/os-release
    echo "deb [signed-by=${keyfile}] https://nginx.org/packages/ubuntu ${VERSION_CODENAME} nginx" \
        > "$listfile"
    echo "deb-src [signed-by=${keyfile}] https://nginx.org/packages/ubuntu ${VERSION_CODENAME} nginx" \
        >> "$listfile"
    apt_update
    log_ok "Dépôt Nginx officiel configuré"
}

_install_nginx() {
    apt_install nginx
}

_configure_nginx() {
    command_exists nginx || { log_error "nginx non trouvé après installation"; return 1; }

    local nginx_conf="/etc/nginx/nginx.conf"
    local sites_available="/etc/nginx/conf.d"

    backup_file "$nginx_conf"

    local template="${DEVLAB_ROOT}/configs/nginx/nginx.conf.tpl"
    if [[ -f "$template" ]]; then
        render_template "$template" "$nginx_conf"
        log_step "nginx.conf configuré depuis template"
    fi

    # Page de statut DevLab
    local devlab_site="${sites_available}/devlab-default.conf"
    if [[ ! -f "$devlab_site" ]]; then
        cat > "$devlab_site" << EOF
server {
    listen ${NGINX_HTTP_PORT:-80} default_server;
    server_name _;

    location / {
        root /var/www/html;
        index index.html;
    }

    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
EOF
        log_step "Site Nginx par défaut configuré"
    fi

    # Page d'accueil DevLab
    mkdir -p /var/www/html
    if [[ ! -f "/var/www/html/index.html" ]]; then
        cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"><title>DevLab AI</title>
<style>body{font-family:monospace;background:#0d1117;color:#c9d1d9;padding:40px}
h1{color:#58a6ff}code{color:#7ee787}</style></head>
<body>
<h1>DevLab AI Laboratory</h1>
<p>Laboratoire de développement IA opérationnel.</p>
<code>devlab status</code> — pour voir l'état des modules
</body></html>
HTML
    fi

    # Test syntaxe et démarrage
    if nginx -t 2>/dev/null; then
        systemctl enable nginx --quiet
        systemctl start nginx 2>/dev/null || systemctl reload nginx 2>/dev/null
        log_ok "Nginx démarré"
    else
        log_error "Configuration Nginx invalide"
        return 1
    fi
}

_do_install() {
    _add_nginx_repo
    _install_nginx
    _configure_nginx
}

installer_run \
    "web/nginx" \
    "Nginx" \
    "nginx -v 2>&1 | awk -F'/' '{print \$2}'" \
    "_do_install"
