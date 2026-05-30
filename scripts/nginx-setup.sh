#!/usr/bin/env bash
# scripts/nginx-setup.sh — Configure nginx + certbot automatiquement
# Usage : bash nginx-setup.sh [--https] [--email EMAIL]

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVLAB_ROOT

source "${DEVLAB_ROOT}/lib/core.sh"

log_section "Configuration Nginx"

# ── Paramètres ───────────────────────────────────────────────────────────────
ENABLE_HTTPS=false
CERTBOT_EMAIL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --https)  ENABLE_HTTPS=true; shift ;;
        --email)  CERTBOT_EMAIL="$2"; shift 2 ;;
        *)        shift ;;
    esac
done

VSCODE_DOMAIN="${GAMADCODE_DOMAIN:-}"
UI_DOMAIN="${GAMADCODE_UI_DOMAIN:-}"
VSCODE_PORT="${CODE_SERVER_PORT:-8080}"
UI_PORT="${GAMADCODE_UI_PORT:-3000}"

# ── Écriture des configs via Python (pas de problème d'échappement) ──────────
_write_nginx_conf() {
    local conf_file="$1"
    local domain="$2"
    local port="$3"
    local label="$4"

    python3 - << PYEOF
domain  = "${domain}"
port    = "${port}"
outfile = "${conf_file}"

content = """server {{
    listen 80;
    server_name {domain};

    location / {{
        proxy_pass http://127.0.0.1:{port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 3600s;
        proxy_buffering off;
    }}
}}
""".format(domain=domain, port=port)

with open(outfile, 'w') as f:
    f.write(content)
print("Écrit : " + outfile)
PYEOF
}

# ── Config VS Code (code-server) ─────────────────────────────────────────────
if [[ -n "$VSCODE_DOMAIN" ]]; then
    _write_nginx_conf \
        "/etc/nginx/conf.d/code-server.conf" \
        "$VSCODE_DOMAIN" \
        "$VSCODE_PORT" \
        "code-server"
    log_ok "Nginx code-server : ${VSCODE_DOMAIN} → :${VSCODE_PORT}"
else
    log_warn "GAMADCODE_DOMAIN non défini — VS Code accessible via IP:${VSCODE_PORT} seulement"
fi

# ── Config GamadCode UI (dashboard) ──────────────────────────────────────────
if [[ -n "$UI_DOMAIN" ]]; then
    _write_nginx_conf \
        "/etc/nginx/conf.d/gamadcode-ui.conf" \
        "$UI_DOMAIN" \
        "$UI_PORT" \
        "gamadcode-ui"
    log_ok "Nginx GamadCode UI : ${UI_DOMAIN} → :${UI_PORT}"
else
    log_warn "GAMADCODE_UI_DOMAIN non défini — dashboard accessible via IP:${UI_PORT} seulement"
fi

# ── Test et rechargement nginx ────────────────────────────────────────────────
if nginx -t 2>/dev/null; then
    systemctl reload nginx 2>/dev/null || systemctl start nginx 2>/dev/null || true
    log_ok "Nginx rechargé"
else
    log_error "Configuration nginx invalide — vérifiez les fichiers dans /etc/nginx/conf.d/"
    nginx -t
    exit 1
fi

# ── Certbot HTTPS ─────────────────────────────────────────────────────────────
if [[ "$ENABLE_HTTPS" == "true" ]]; then
    log_section "Certificats HTTPS (Let's Encrypt)"

    if ! command -v certbot &>/dev/null; then
        log_step "Installation certbot…"
        apt-get install -y certbot python3-certbot-nginx -qq
        log_ok "certbot installé"
    fi

    if [[ -z "$CERTBOT_EMAIL" ]]; then
        log_error "Email requis pour certbot : devlab nginx --https --email ton@email.com"
        exit 1
    fi

    local domains_args=""
    [[ -n "$VSCODE_DOMAIN" ]] && domains_args="$domains_args -d $VSCODE_DOMAIN"
    [[ -n "$UI_DOMAIN"     ]] && domains_args="$domains_args -d $UI_DOMAIN"

    if [[ -z "$domains_args" ]]; then
        log_warn "Aucun domaine configuré — certbot ignoré"
    else
        log_step "Obtention certificat pour :${domains_args}…"
        # shellcheck disable=SC2086
        certbot --nginx $domains_args \
            --non-interactive \
            --agree-tos \
            --email "$CERTBOT_EMAIL" \
            --redirect
        log_ok "HTTPS activé !"
        [[ -n "$VSCODE_DOMAIN" ]] && log_info "VS Code  : https://${VSCODE_DOMAIN}"
        [[ -n "$UI_DOMAIN"     ]] && log_info "Dashboard: https://${UI_DOMAIN}"
    fi
else
    echo
    log_info "Pour activer HTTPS : devlab nginx --https --email ton@email.com"
    [[ -n "$VSCODE_DOMAIN" ]] && log_info "VS Code  : http://${VSCODE_DOMAIN} (HTTP pour l'instant)"
    [[ -n "$UI_DOMAIN"     ]] && log_info "Dashboard: http://${UI_DOMAIN} (HTTP pour l'instant)"
fi
