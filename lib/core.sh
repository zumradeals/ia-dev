#!/usr/bin/env bash
# lib/core.sh — Bibliothèque centrale : logging, couleurs, utilitaires
# À sourcer en tête de chaque script : source "${DEVLAB_ROOT}/lib/core.sh"

# Fail fast : erreur non capturée = arrêt immédiat
set -euo pipefail

# ─────────────────────────────────────────────
# DEVLAB_ROOT — détection automatique
# ─────────────────────────────────────────────
if [[ -z "${DEVLAB_ROOT:-}" ]]; then
    DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
export DEVLAB_ROOT

# ─────────────────────────────────────────────
# CHARGEMENT CONFIGURATION
# ─────────────────────────────────────────────
_load_config() {
    local default_env="${DEVLAB_ROOT}/config/default.env"
    local versions_conf="${DEVLAB_ROOT}/config/versions.conf"
    local local_env="${DEVLAB_ROOT}/config/local.env"
    local secrets_env="${DEVLAB_ROOT}/config/secrets.env"

    # shellcheck source=/dev/null
    [[ -f "$default_env" ]]  && source "$default_env"
    # shellcheck source=/dev/null
    [[ -f "$versions_conf" ]] && source "$versions_conf"
    # shellcheck source=/dev/null
    [[ -f "$local_env" ]]    && source "$local_env"
    # shellcheck source=/dev/null
    [[ -f "$secrets_env" ]]  && source "$secrets_env"
}
_load_config

# ─────────────────────────────────────────────
# COULEURS (désactivées si non-TTY)
# ─────────────────────────────────────────────
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" == "" ]]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
    C_RED='\033[0;31m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_BLUE='\033[0;34m'
    C_CYAN='\033[0;36m'
    C_WHITE='\033[1;37m'
else
    C_RESET=''; C_BOLD=''; C_DIM=''
    C_RED=''; C_GREEN=''; C_YELLOW=''
    C_BLUE=''; C_CYAN=''; C_WHITE=''
fi
export C_RESET C_BOLD C_DIM C_RED C_GREEN C_YELLOW C_BLUE C_CYAN C_WHITE

# ─────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────
DEVLAB_MODULE="${DEVLAB_MODULE:-main}"
LOG_FILE=""
ERROR_LOG=""

log_init() {
    # Usage: log_init <module_name> [category]
    # category: bootstrap | install | maintenance (default: install)
    local module="${1:-main}"
    local category="${2:-install}"
    local ts; ts=$(date +%Y%m%d_%H%M%S)
    local log_base="${DEVLAB_ROOT}/logs"

    mkdir -p "${log_base}/${category}" "${log_base}/errors"

    LOG_FILE="${log_base}/${category}/${ts}_${module}.log"
    ERROR_LOG="${log_base}/errors/${ts}_${module}.error.log"
    export LOG_FILE ERROR_LOG DEVLAB_MODULE="$module"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [${module}] Log initialized — DevLab ${DEVLAB_VERSION:-1.0.0}" >> "$LOG_FILE"
}

_write_log() {
    local level="$1"; shift
    local msg="$*"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    local line="[${ts}] [${level}] [${DEVLAB_MODULE}] ${msg}"

    [[ -n "${LOG_FILE}"  ]] && echo "$line" >> "$LOG_FILE"

    if [[ "$level" == "ERROR" || "$level" == "FATAL" ]]; then
        [[ -n "${ERROR_LOG}" ]] && echo "$line" >> "$ERROR_LOG"
    fi
}

log_debug() {
    [[ "${LOG_LEVEL:-INFO}" == "DEBUG" ]] || return 0
    _write_log "DEBUG" "$*"
    printf "${C_DIM}[DEBUG] %s${C_RESET}\n" "$*" >&2
}

log_info() {
    _write_log "INFO" "$*"
    printf "${C_BLUE}[INFO]${C_RESET}  %s\n" "$*"
}

log_ok() {
    _write_log "OK" "$*"
    printf "${C_GREEN}[OK]${C_RESET}    %s\n" "$*"
}

log_skip() {
    _write_log "SKIP" "$*"
    printf "${C_CYAN}[SKIP]${C_RESET}  %s\n" "$*"
}

log_warn() {
    _write_log "WARN" "$*"
    printf "${C_YELLOW}[WARN]${C_RESET}  %s\n" "$*" >&2
}

log_error() {
    _write_log "ERROR" "$*"
    printf "${C_RED}[ERROR]${C_RESET} %s\n" "$*" >&2
}

log_fatal() {
    _write_log "FATAL" "$*"
    printf "${C_RED}${C_BOLD}[FATAL]${C_RESET} %s\n" "$*" >&2
    exit 1
}

log_section() {
    local msg="$*"
    printf "\n${C_BOLD}${C_WHITE}━━━ %s ━━━${C_RESET}\n\n" "$msg"
    _write_log "INFO" "=== ${msg} ==="
}

log_step() {
    printf "    ${C_DIM}→${C_RESET} %s\n" "$*"
    _write_log "INFO" "  → $*"
}

# ─────────────────────────────────────────────
# CONTRÔLE D'EXÉCUTION
# ─────────────────────────────────────────────
require_root() {
    [[ "$(id -u)" -eq 0 ]] || log_fatal "Cette opération requiert les droits root. Utilisez sudo."
}

require_no_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        log_warn "Exécution en root — certaines opérations délèguent à ${DEVLAB_USER:-devuser}"
    fi
}

confirm() {
    local prompt="${1:-Continuer ?}"
    [[ "${DEVLAB_AUTO_CONFIRM:-false}" == "true" ]] && return 0
    printf "${C_YELLOW}%s [y/N] ${C_RESET}" "$prompt"
    read -r _response
    [[ "$_response" =~ ^[Yy]$ ]]
}

dry_run_guard() {
    # Usage: dry_run_guard commande...
    # En mode dry-run, affiche sans exécuter
    if [[ "${DEVLAB_DRY_RUN:-false}" == "true" ]]; then
        printf "${C_DIM}[DRY-RUN] %s${C_RESET}\n" "$*"
        return 0
    fi
    "$@"
}

# ─────────────────────────────────────────────
# UTILITAIRES SYSTÈME
# ─────────────────────────────────────────────
command_exists() {
    command -v "$1" &>/dev/null
}

is_ubuntu() {
    [[ -f /etc/os-release ]] || return 1
    # shellcheck source=/dev/null
    source /etc/os-release
    [[ "$ID" == "ubuntu" ]]
}

is_ubuntu_2404() {
    [[ -f /etc/os-release ]] || return 1
    # shellcheck source=/dev/null
    source /etc/os-release
    [[ "$ID" == "ubuntu" && "$VERSION_ID" == "24.04" ]]
}

get_arch() {
    uname -m
}

backup_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    local backup="${file}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$file" "$backup"
    log_info "Backup : ${file} → ${backup}"
}

append_if_missing() {
    # Ajoute une ligne dans un fichier seulement si elle n'y est pas déjà
    local line="$1"
    local file="$2"
    grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

run_as_devuser() {
    # Exécute une commande en tant que DEVLAB_USER si on est root
    local user="${DEVLAB_USER:-devuser}"
    if [[ "$(id -u)" -eq 0 ]]; then
        sudo -u "$user" bash -lc "$*"
    else
        bash -c "$*"
    fi
}

ensure_dir() {
    # Crée un répertoire et lui affecte le bon propriétaire
    local dir="$1"
    local owner="${2:-${DEVLAB_USER:-devuser}}"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        chown "${owner}:${DEVLAB_GROUP:-devlab}" "$dir" 2>/dev/null || true
        log_step "Répertoire créé : $dir"
    fi
}

render_template() {
    # Substitue les variables d'environnement dans un fichier .tpl
    local template="$1"
    local output="$2"
    [[ -f "$template" ]] || log_fatal "Template introuvable : $template"
    envsubst < "$template" > "$output"
    log_step "Template rendu : ${template} → ${output}"
}

# ─────────────────────────────────────────────
# BANNIÈRE
# ─────────────────────────────────────────────
devlab_banner() {
    printf "${C_BOLD}${C_BLUE}"
    cat << 'BANNER'

  ██████╗ ███████╗██╗   ██╗██╗      █████╗ ██████╗
  ██╔══██╗██╔════╝██║   ██║██║     ██╔══██╗██╔══██╗
  ██║  ██║█████╗  ██║   ██║██║     ███████║██████╔╝
  ██║  ██║██╔══╝  ╚██╗ ██╔╝██║     ██╔══██║██╔══██╗
  ██████╔╝███████╗ ╚████╔╝ ███████╗██║  ██║██████╔╝
  ╚═════╝ ╚══════╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝╚═════╝

  AI Development Laboratory Bootstrap System v1.0
BANNER
    printf "${C_RESET}\n"
}
