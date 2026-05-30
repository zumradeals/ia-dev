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
<head>
<meta charset="UTF-8">
<title>DevLab AI</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: monospace; background: #0d1117; color: #c9d1d9; min-height: 100vh; display: flex; align-items: center; justify-content: center; }
  .card { text-align: center; padding: 60px 40px; }
  h1 { color: #58a6ff; font-size: 2rem; margin-bottom: 8px; letter-spacing: 2px; }
  .subtitle { color: #8b949e; margin-bottom: 48px; font-size: 0.9rem; }
  .btn {
    display: inline-flex; align-items: center; gap: 10px;
    background: #238636; color: #fff; text-decoration: none;
    padding: 16px 36px; border-radius: 8px; font-size: 1rem;
    font-family: monospace; font-weight: bold; letter-spacing: 1px;
    transition: background 0.2s;
  }
  .btn:hover { background: #2ea043; }
  .btn svg { width: 20px; height: 20px; fill: currentColor; }
  .footer { margin-top: 40px; color: #484f58; font-size: 0.75rem; }
  code { color: #7ee787; }
</style>
</head>
<body>
<div class="card">
  <h1>DevLab AI</h1>
  <p class="subtitle">Laboratoire de développement IA opérationnel</p>
  <a class="btn" href="/code/" target="_blank">
    <svg viewBox="0 0 24 24"><path d="M13.5 2C13.5 2 13.5 2 13.5 2C8 2 3.5 6.5 3.5 12C3.5 17.5 8 22 13.5 22C19 22 23.5 17.5 23.5 12C23.5 6.5 19 2 13.5 2ZM13.5 20C9.1 20 5.5 16.4 5.5 12C5.5 7.6 9.1 4 13.5 4C17.9 4 21.5 7.6 21.5 12C21.5 16.4 17.9 20 13.5 20ZM12 7L17 12L12 17L10.6 15.6L13.2 13H7V11H13.2L10.6 8.4L12 7Z"/></svg>
    Ouvrir VS Code
  </a>
  <p class="footer"><code>devlab status</code> — état des modules</p>
</div>
</body>
</html>
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
