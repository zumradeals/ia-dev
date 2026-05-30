#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# GamadCode — Installateur automatique
# Usage : bash /devlab/install.sh
# Cloner d'abord : git clone https://github.com/zumradeals/ia-dev /devlab
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_LOG="${DEVLAB_ROOT}/logs/install-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "${DEVLAB_ROOT}/logs"
exec > >(stdbuf -oL tee -a "$INSTALL_LOG") 2>&1

# ─── Couleurs ────────────────────────────────────────────────────────────────
C_RESET='\033[0m'; C_BOLD='\033[1m'; C_DIM='\033[2m'
C_GREEN='\033[0;32m'; C_CYAN='\033[0;36m'; C_YELLOW='\033[0;33m'
C_RED='\033[0;31m'; C_BLUE='\033[0;34m'

# ─── Helpers ─────────────────────────────────────────────────────────────────
die()     { echo -e "\n  ${C_RED}${C_BOLD}✗ ERREUR :${C_RESET} $*\n" >&2; exit 1; }
ok()      { echo -e "  ${C_GREEN}✓${C_RESET}  $*"; }
info()    { echo -e "  ${C_CYAN}ℹ${C_RESET}  $*"; }
warn()    { echo -e "  ${C_YELLOW}⚠${C_RESET}  $*"; }
section() { echo -e "\n${C_BOLD}${C_CYAN}┌─ $* ${C_RESET}"; }
hr()      { echo -e "${C_DIM}────────────────────────────────────────────${C_RESET}"; }

ask() {
    local prompt="$1" default="${2:-}" varname="$3"
    local hint=""
    [[ -n "$default" ]] && hint=" ${C_DIM}[${default}]${C_RESET}"
    # Lire depuis /dev/tty pour contourner le tee
    echo -ne "  ${C_BOLD}${prompt}${C_RESET}${hint} : " >/dev/tty
    local value; read -r value </dev/tty
    [[ -z "$value" && -n "$default" ]] && value="$default"
    printf -v "$varname" '%s' "$value"
}

ask_secret() {
    local prompt="$1" varname="$2"
    echo -ne "  ${C_BOLD}${prompt}${C_RESET} ${C_DIM}(masqué)${C_RESET} : " >/dev/tty
    local value; read -rs value </dev/tty; echo >/dev/tty
    printf -v "$varname" '%s' "$value"
}

ask_yn() {
    local prompt="$1" default="${2:-o}"
    local hint; [[ "${default,,}" =~ ^(o|y) ]] && hint="O/n" || hint="o/N"
    echo -ne "  ${C_BOLD}${prompt}${C_RESET} ${C_DIM}[${hint}]${C_RESET} : " >/dev/tty
    local ans; read -r ans </dev/tty
    [[ -z "$ans" ]] && ans="$default"
    [[ "${ans,,}" =~ ^(o|oui|y|yes)$ ]]
}

gen_secret() { openssl rand -hex 32 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c 64; }
get_public_ip() {
    curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null \
        || curl -fsSL --max-time 5 https://ifconfig.me 2>/dev/null \
        || hostname -I | awk '{print $1}'
}

run_step() {
    local label="$1"; shift
    echo -ne "  ${C_CYAN}…${C_RESET}  ${label}… "
    if "$@" >>"$INSTALL_LOG" 2>&1; then
        echo -e "\r  ${C_GREEN}✓${C_RESET}  ${label}   "
    else
        echo -e "\r  ${C_RED}✗${C_RESET}  ${label} — voir ${INSTALL_LOG}"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# VÉRIFICATIONS INITIALES
# ═══════════════════════════════════════════════════════════════════════════════
[[ "$(id -u)" -eq 0 ]] || die "Lancez ce script en root :  sudo bash $0"
[[ -f "${DEVLAB_ROOT}/bin/devlab" ]] || die "Répertoire invalide. Clonez d'abord le repo dans /devlab"

# ─── Banner ───────────────────────────────────────────────────────────────────
clear
echo
echo -e "  ${C_BOLD}${C_CYAN}╔══════════════════════════════════════════════╗${C_RESET}"
echo -e "  ${C_BOLD}${C_CYAN}║   GamadCode — Installateur automatique  v2   ║${C_RESET}"
echo -e "  ${C_BOLD}${C_CYAN}║   Cloud Dev Platform                         ║${C_RESET}"
echo -e "  ${C_BOLD}${C_CYAN}╚══════════════════════════════════════════════╝${C_RESET}"
echo
info "Ce script installe et configure GamadCode de A à Z."
info "Durée estimée : ${C_BOLD}5 à 15 minutes${C_RESET} selon la connexion."
echo
info "Log complet : ${C_DIM}${INSTALL_LOG}${C_RESET}"
echo

echo -ne "  ${C_CYAN}…${C_RESET}  Détection de l'IP publique… "
SERVER_IP="$(get_public_ip)"
echo -e "  ${C_GREEN}${C_BOLD}${SERVER_IP}${C_RESET}"

# ═══════════════════════════════════════════════════════════════════════════════
# COLLECTE DES INFORMATIONS
# ═══════════════════════════════════════════════════════════════════════════════

section "DOMAINES & HTTPS"
echo
info "Si vos domaines DNS pointent déjà sur ce serveur, entrez-les."
info "Sinon laissez vide — l'accès se fera par IP."
echo
ask "Domaine VS Code  (ex: code.gamad.net, vide = IP)" "" VSCODE_DOMAIN
ask "Domaine Dashboard (ex: app.gamad.net, vide = IP)" "" UI_DOMAIN

HTTPS_EMAIL=""
ENABLE_HTTPS=false
if [[ -n "$VSCODE_DOMAIN" || -n "$UI_DOMAIN" ]]; then
    echo
    if ask_yn "Activer HTTPS automatiquement (Let's Encrypt) ?"; then
        ask "Votre email pour Let's Encrypt" "" HTTPS_EMAIL
        [[ -n "$HTTPS_EMAIL" ]] && ENABLE_HTTPS=true || warn "Email vide — HTTPS désactivé"
    fi
fi

section "SÉCURITÉ"
echo
AUTO_PG_PASS="$(gen_secret | cut -c1-20)"
info "Mot de passe PostgreSQL auto-généré. Appuyez Entrée pour l'utiliser tel quel."
ask "Mot de passe PostgreSQL" "$AUTO_PG_PASS" POSTGRES_PASSWORD
[[ -z "$POSTGRES_PASSWORD" ]] && die "Le mot de passe PostgreSQL ne peut pas être vide"

section "GITHUB OAUTH (admin dashboard — optionnel)"
echo
info "Permet de se connecter au dashboard admin via GitHub."
info "Créez une OAuth App sur : https://github.com/settings/applications/new"
info "Appuyez Entrée pour ignorer cette section."
echo

GITHUB_CLIENT_ID="" GITHUB_CLIENT_SECRET="" ADMIN_GITHUB_LOGIN="" GITHUB_CALLBACK_URL=""

if ask_yn "Configurer GitHub OAuth ?" "n"; then
    ask    "GitHub Client ID"     "" GITHUB_CLIENT_ID
    ask_secret "GitHub Client Secret" GITHUB_CLIENT_SECRET
    ask    "Votre login GitHub (sera admin)" "" ADMIN_GITHUB_LOGIN
    if [[ -n "$UI_DOMAIN" && "$ENABLE_HTTPS" == true ]]; then
        DEFAULT_CB="https://${UI_DOMAIN}/auth/github/callback"
    elif [[ -n "$UI_DOMAIN" ]]; then
        DEFAULT_CB="http://${UI_DOMAIN}/auth/github/callback"
    else
        DEFAULT_CB="http://${SERVER_IP}:3000/auth/github/callback"
    fi
    ask "Callback URL" "$DEFAULT_CB" GITHUB_CALLBACK_URL
fi

section "CLAUDE CODE (optionnel)"
echo
info "Votre clé API Anthropic sera disponible dans votre environnement VS Code."
ask_secret "Clé API Anthropic (sk-ant-…, vide = ignorer)" ANTHROPIC_API_KEY

# ═══════════════════════════════════════════════════════════════════════════════
# RÉCAPITULATIF & CONFIRMATION
# ═══════════════════════════════════════════════════════════════════════════════
section "RÉCAPITULATIF"
echo
echo -e "  ${C_BOLD}Ce qui sera installé :${C_RESET}"
echo
ok "Node.js (LTS) + npm"
ok "PostgreSQL 16"
ok "Docker + Compose"
ok "Nginx"
ok "code-server (VS Code dans le navigateur)"
ok "GamadCode Web UI"
ok "Outils : zsh, tmux, fzf, git, gh CLI, ripgrep, bat"
[[ -n "$ANTHROPIC_API_KEY" ]] && ok "Claude Code (CLI)"
echo
echo -e "  ${C_BOLD}Accès :${C_RESET}"
if [[ -n "$VSCODE_DOMAIN" ]]; then
    ok "VS Code    → http${ENABLE_HTTPS:+s}://${VSCODE_DOMAIN}"
else
    info "VS Code    → http://${SERVER_IP}:8080"
fi
if [[ -n "$UI_DOMAIN" ]]; then
    ok "Dashboard  → http${ENABLE_HTTPS:+s}://${UI_DOMAIN}"
else
    info "Dashboard  → http://${SERVER_IP}:3000"
fi
[[ "$ENABLE_HTTPS" == true ]] && ok "HTTPS Let's Encrypt : ${HTTPS_EMAIL}"
[[ -n "$GITHUB_CLIENT_ID" ]] && ok "GitHub OAuth (admin : ${ADMIN_GITHUB_LOGIN})" || info "GitHub OAuth : désactivé"
echo
hr

echo
ask_yn "${C_BOLD}Lancer l'installation ?${C_RESET}" "o" || { warn "Installation annulée."; exit 0; }

SESSION_SECRET="$(gen_secret)"
echo

# ═══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 1 — BOOTSTRAP SYSTÈME
# ═══════════════════════════════════════════════════════════════════════════════
section "ÉTAPE 1/7 — Bootstrap système"
echo

run_step "Pré-vérifications"       bash "${DEVLAB_ROOT}/bootstrap/00-preflight.sh"
run_step "Paquets de base"         bash "${DEVLAB_ROOT}/bootstrap/10-base-packages.sh"
run_step "Sécurité système"        bash "${DEVLAB_ROOT}/bootstrap/20-security.sh"
run_step "Utilisateurs et groupes" bash "${DEVLAB_ROOT}/bootstrap/30-users-groups.sh"
run_step "Répertoires DevLab"      bash "${DEVLAB_ROOT}/bootstrap/40-directories.sh"

# ═══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 2 — ÉCRITURE DE LA CONFIG (avant l'install pour que les services démarrent bien)
# ═══════════════════════════════════════════════════════════════════════════════
section "ÉTAPE 2/7 — Configuration"
echo

LOCAL_ENV="${DEVLAB_ROOT}/config/local.env"
SECRETS_ENV="${DEVLAB_ROOT}/config/secrets.env"

cat > "$LOCAL_ENV" << ENVEOF
# Généré par install.sh — $(date -u +"%Y-%m-%dT%H:%M:%SZ")
GAMADCODE_DOMAIN="${VSCODE_DOMAIN}"
GAMADCODE_UI_DOMAIN="${UI_DOMAIN}"
GAMADCODE_UI_PORT="3000"
CODE_SERVER_PORT="8080"
GAMADCODE_PROJECT_NAME="GamadCode"

POSTGRES_DB="gamadcode"
POSTGRES_USER="gamadcode"
POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"

WORKSPACE_BASE="/opt/gamadcode/users"
CODE_SERVER_IMAGE="codercom/code-server:latest"

ADMIN_GITHUB_LOGIN="${ADMIN_GITHUB_LOGIN}"
GITHUB_CALLBACK_URL="${GITHUB_CALLBACK_URL}"

GIT_DEFAULT_BRANCH="main"
ENVEOF

cat > "$SECRETS_ENV" << SECRETEOF
# GamadCode secrets — chmod 600 — NE PAS COMMITER
SESSION_SECRET="${SESSION_SECRET}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
GITHUB_CLIENT_ID="${GITHUB_CLIENT_ID}"
GITHUB_CLIENT_SECRET="${GITHUB_CLIENT_SECRET}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"
SECRETEOF

chmod 600 "$SECRETS_ENV"
ok "config/local.env écrit"
ok "config/secrets.env écrit (chmod 600)"

# Activer les modules requis dans modules.conf
MODULES_CONF="${DEVLAB_ROOT}/config/modules.conf"
enable_module() {
    local key="$1"
    if grep -q "^${key}=" "$MODULES_CONF" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=true|" "$MODULES_CONF"
    fi
}

enable_module "MODULE_BASE_SYSTEM_TOOLS"
enable_module "MODULE_LANGUAGES_NODEJS"
enable_module "MODULE_CONTAINERS_DOCKER"
enable_module "MODULE_DATABASES_POSTGRESQL"
enable_module "MODULE_WEB_NGINX"
enable_module "MODULE_WEB_GAMADCODE_UI"
enable_module "MODULE_DEVTOOLS_ZSH"
enable_module "MODULE_DEVTOOLS_TMUX"
enable_module "MODULE_DEVTOOLS_FZF"
enable_module "MODULE_DEVTOOLS_MODERN_CLI"
enable_module "MODULE_DEVTOOLS_GIT_GITHUB"
enable_module "MODULE_DEVTOOLS_CODE_SERVER"
[[ -n "$ANTHROPIC_API_KEY" ]] && enable_module "MODULE_AI_CLAUDE_CODE"

ok "modules.conf configuré"

# ═══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 3 — INSTALLATION DES MODULES
# ═══════════════════════════════════════════════════════════════════════════════
section "ÉTAPE 3/7 — Installation des modules"
echo
info "Cette étape peut prendre plusieurs minutes…"
echo

# Source les env pour que les installeurs les voient
set -a
# shellcheck source=/dev/null
[[ -f "${DEVLAB_ROOT}/config/default.env" ]] && source "${DEVLAB_ROOT}/config/default.env"
[[ -f "$LOCAL_ENV"   ]] && source "$LOCAL_ENV"
[[ -f "$SECRETS_ENV" ]] && source "$SECRETS_ENV"
set +a

# Lien symlink vers /usr/local/bin pour que 'devlab' soit accessible
ln -sf "${DEVLAB_ROOT}/bin/devlab" /usr/local/bin/devlab 2>/dev/null || true

bash "${DEVLAB_ROOT}/bin/devlab" install all
echo
ok "Tous les modules installés"

# ═══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 4 — BASE DE DONNÉES
# ═══════════════════════════════════════════════════════════════════════════════
section "ÉTAPE 4/7 — Base de données PostgreSQL"
echo

# S'assurer que PostgreSQL tourne
run_step "Démarrage PostgreSQL" systemctl start postgresql

# Créer DB et user de façon idempotente
run_step "Création DB gamadcode" bash -c \
    "sudo -u postgres psql -tc \"SELECT 1 FROM pg_database WHERE datname='gamadcode'\" | grep -q 1 \
     || sudo -u postgres psql -c \"CREATE DATABASE gamadcode;\""

run_step "Création user gamadcode" bash -c \
    "sudo -u postgres psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='gamadcode'\" | grep -q 1 \
     || sudo -u postgres psql -c \"CREATE USER gamadcode WITH PASSWORD '${POSTGRES_PASSWORD}';\""

run_step "Synchronisation mot de passe" bash -c \
    "sudo -u postgres psql -c \"ALTER USER gamadcode WITH PASSWORD '${POSTGRES_PASSWORD}';\""

run_step "Droits sur la DB" bash -c \
    "sudo -u postgres psql -c \"GRANT ALL PRIVILEGES ON DATABASE gamadcode TO gamadcode;\""
run_step "Droits schema public" bash -c \
    "sudo -u postgres psql -d gamadcode -c \"GRANT ALL ON SCHEMA public TO gamadcode;\""

ok "Base de données gamadcode prête"

# ═══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 5 — GAMADCODE WEB UI
# ═══════════════════════════════════════════════════════════════════════════════
section "ÉTAPE 5/7 — GamadCode Web UI"
echo

WEB_DIR="${DEVLAB_ROOT}/web"
cd "$WEB_DIR"

# Charger nvm si présent
NVM_SCRIPT="${HOME}/.nvm/nvm.sh"
[[ -s "$NVM_SCRIPT" ]] && source "$NVM_SCRIPT"

run_step "npm install" npm install --omit=dev --silent
run_step "Migration base de données" node scripts/migrate.js

# Créer le dossier workspaces
mkdir -p /opt/gamadcode/users

# Redémarrer le service pour prendre la nouvelle config
run_step "Redémarrage gamadcode-ui" systemctl restart gamadcode-ui

# Attendre que le service soit opérationnel
echo -ne "  ${C_CYAN}…${C_RESET}  Vérification démarrage… "
sleep 3
if systemctl is-active --quiet gamadcode-ui; then
    echo -e "\r  ${C_GREEN}✓${C_RESET}  GamadCode UI démarré sur le port 3000   "
else
    echo -e "\r  ${C_YELLOW}⚠${C_RESET}  Service démarré avec délai — voir : journalctl -u gamadcode-ui -n 30"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 6 — NGINX & HTTPS
# ═══════════════════════════════════════════════════════════════════════════════
section "ÉTAPE 6/7 — Nginx & HTTPS"
echo

run_step "Démarrage Nginx" systemctl start nginx

if [[ -n "$VSCODE_DOMAIN" || -n "$UI_DOMAIN" ]]; then
    if [[ "$ENABLE_HTTPS" == true ]]; then
        run_step "Configuration Nginx + HTTPS" \
            bash "${DEVLAB_ROOT}/scripts/nginx-setup.sh" --https --email "$HTTPS_EMAIL"
        ok "Nginx configuré avec HTTPS (Let's Encrypt)"
    else
        run_step "Configuration Nginx (HTTP)" \
            bash "${DEVLAB_ROOT}/scripts/nginx-setup.sh"
        ok "Nginx configuré (HTTP)"
    fi
else
    info "Aucun domaine configuré — Nginx accessible par IP uniquement"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 7 — FIREWALL
# ═══════════════════════════════════════════════════════════════════════════════
section "ÉTAPE 7/7 — Firewall"
echo

if command -v ufw &>/dev/null; then
    run_step "Ports standards (22, 80, 443, 3000, 8080)"   ufw allow 22/tcp
    ufw allow 80/tcp  >>"$INSTALL_LOG" 2>&1
    ufw allow 443/tcp >>"$INSTALL_LOG" 2>&1
    ufw allow 3000/tcp >>"$INSTALL_LOG" 2>&1
    ufw allow 8080/tcp >>"$INSTALL_LOG" 2>&1
    run_step "Ports workspaces Docker (10000-20000)"        ufw allow 10000:20000/tcp
    ufw --force enable >>"$INSTALL_LOG" 2>&1 || true
    ok "Firewall configuré"
else
    info "ufw non disponible — vérifiez manuellement les ports ouverts"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# RÉSUMÉ FINAL
# ═══════════════════════════════════════════════════════════════════════════════

# Construire les URLs d'accès
if [[ -n "$UI_DOMAIN" ]]; then
    DASHBOARD_URL="http${ENABLE_HTTPS:+s}://${UI_DOMAIN}"
else
    DASHBOARD_URL="http://${SERVER_IP}:3000"
fi

if [[ -n "$VSCODE_DOMAIN" ]]; then
    VSCODE_URL="http${ENABLE_HTTPS:+s}://${VSCODE_DOMAIN}"
else
    VSCODE_URL="http://${SERVER_IP}:8080"
fi

# Sauvegarder un fichier de résumé
SUMMARY_FILE="/root/gamadcode-access.txt"
cat > "$SUMMARY_FILE" << SUMMARY
══════════════════════════════════════════════════
  GamadCode — Informations d'accès
  Installé le $(date "+%d/%m/%Y à %H:%M")
══════════════════════════════════════════════════

Dashboard (inscription/connexion) :
  ${DASHBOARD_URL}

VS Code dans le navigateur :
  ${VSCODE_URL}

Base de données :
  Host     : localhost:5432
  Base     : gamadcode
  User     : gamadcode
  Password : ${POSTGRES_PASSWORD}

Fichiers de config :
  ${LOCAL_ENV}
  ${SECRETS_ENV}

Log d'installation :
  ${INSTALL_LOG}

Commandes utiles :
  systemctl status gamadcode-ui
  systemctl restart gamadcode-ui
  journalctl -u gamadcode-ui -f
  devlab status
  devlab health
SUMMARY
chmod 600 "$SUMMARY_FILE"

# Affichage final
echo
echo
echo -e "  ${C_BOLD}${C_GREEN}╔══════════════════════════════════════════════╗${C_RESET}"
echo -e "  ${C_BOLD}${C_GREEN}║   ✓  Installation terminée avec succès !     ║${C_RESET}"
echo -e "  ${C_BOLD}${C_GREEN}╚══════════════════════════════════════════════╝${C_RESET}"
echo
echo -e "  ${C_BOLD}Accès à GamadCode :${C_RESET}"
echo
echo -e "  ${C_BOLD}${C_CYAN}  Dashboard   →  ${C_RESET}${C_BOLD}${DASHBOARD_URL}${C_RESET}"
echo -e "  ${C_BOLD}${C_CYAN}  VS Code     →  ${C_RESET}${C_BOLD}${VSCODE_URL}${C_RESET}"
echo
echo -e "  ${C_DIM}Informations complètes sauvegardées dans :${C_RESET}"
echo -e "  ${C_DIM}${SUMMARY_FILE}${C_RESET}"
echo
echo -e "  ${C_BOLD}Première connexion :${C_RESET} ouvrez le Dashboard, cliquez ${C_BOLD}\"Commencer\"${C_RESET},"
echo -e "  créez votre compte et démarrez votre environnement."
echo
hr
