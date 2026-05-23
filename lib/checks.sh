#!/usr/bin/env bash
# lib/checks.sh — Détection de versions, vérifications pré-installation
# Requiert lib/core.sh déjà sourcé

# ─────────────────────────────────────────────
# VÉRIFICATIONS SYSTÈME
# ─────────────────────────────────────────────
check_os() {
    log_info "Vérification OS..."
    if ! is_ubuntu; then
        log_fatal "Système non supporté. Ubuntu requis (détecté: $(uname -s))"
    fi
    # shellcheck source=/dev/null
    source /etc/os-release
    log_ok "OS : ${PRETTY_NAME}"
}

check_arch() {
    local arch; arch=$(get_arch)
    case "$arch" in
        x86_64|amd64) log_ok "Architecture : ${arch}" ;;
        aarch64|arm64) log_warn "Architecture ARM64 — certains outils peuvent manquer" ;;
        *) log_fatal "Architecture non supportée : ${arch}" ;;
    esac
}

check_disk_space() {
    local min_gb="${1:-10}"
    local available_kb; available_kb=$(df "${DEVLAB_ROOT:-/}" --output=avail 2>/dev/null | tail -1)
    local available_gb=$(( available_kb / 1024 / 1024 ))

    if [[ "$available_gb" -lt "$min_gb" ]]; then
        log_fatal "Espace disque insuffisant : ${available_gb}GB disponible, ${min_gb}GB requis"
    fi
    log_ok "Espace disque : ${available_gb}GB disponible"
}

check_network() {
    log_info "Vérification connectivité réseau..."
    if ! curl -fsS --max-time 10 https://archive.ubuntu.com > /dev/null 2>&1; then
        log_fatal "Pas de connectivité réseau vers archive.ubuntu.com"
    fi
    log_ok "Connectivité réseau : OK"
}

check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        log_warn "sudo sans mot de passe non configuré — certaines étapes demanderont votre mot de passe"
    else
        log_ok "sudo : disponible"
    fi
}

check_ram() {
    local min_mb="${1:-1024}"
    local total_mb; total_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    if [[ "$total_mb" -lt "$min_mb" ]]; then
        log_warn "RAM faible : ${total_mb}MB (minimum recommandé : ${min_mb}MB)"
    else
        log_ok "RAM : ${total_mb}MB"
    fi
}

# ─────────────────────────────────────────────
# VÉRIFICATION COMMANDES / OUTILS
# ─────────────────────────────────────────────
check_command_version() {
    # Usage: check_command_version <cmd> <version_flag>
    # Retourne la version ou "not found"
    local cmd="$1"
    local flag="${2:---version}"
    if command_exists "$cmd"; then
        "$cmd" "$flag" 2>&1 | head -1
    else
        echo "not found"
    fi
}

check_apt_package() {
    # Retourne 0 si le paquet APT est installé
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

check_service_running() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null
}

check_service_enabled() {
    local service="$1"
    systemctl is-enabled --quiet "$service" 2>/dev/null
}

check_port_open() {
    local port="$1"
    ss -tlnp 2>/dev/null | grep -q ":${port}\b"
}

check_user_exists() {
    id "$1" &>/dev/null
}

check_group_exists() {
    getent group "$1" &>/dev/null
}

# ─────────────────────────────────────────────
# VÉRIFICATIONS MODULES SPÉCIFIQUES
# ─────────────────────────────────────────────
check_node() {
    command_exists node && node --version 2>/dev/null || echo ""
}

check_npm() {
    command_exists npm && npm --version 2>/dev/null || echo ""
}

check_python() {
    command_exists python3 && python3 --version 2>/dev/null | awk '{print $2}' || echo ""
}

check_php() {
    command_exists php && php --version 2>/dev/null | head -1 | awk '{print $2}' || echo ""
}

check_docker() {
    command_exists docker && docker --version 2>/dev/null | awk '{print $3}' | tr -d ',' || echo ""
}

check_docker_compose() {
    if command_exists docker; then
        docker compose version 2>/dev/null | awk '{print $NF}' || echo ""
    else
        echo ""
    fi
}

check_go() {
    command_exists go && go version 2>/dev/null | awk '{print $3}' | tr -d 'go' || echo ""
}

check_rust() {
    command_exists rustc && rustc --version 2>/dev/null | awk '{print $2}' || echo ""
}

check_postgres() {
    command_exists psql && psql --version 2>/dev/null | awk '{print $3}' || echo ""
}

check_redis() {
    command_exists redis-cli && redis-cli --version 2>/dev/null | awk '{print $2}' || echo ""
}

check_nginx() {
    command_exists nginx && nginx -v 2>&1 | awk -F'/' '{print $2}' || echo ""
}

# ─────────────────────────────────────────────
# RAPPORT DE STATUT
# ─────────────────────────────────────────────
print_check_row() {
    local label="$1"
    local value="$2"
    if [[ -n "$value" && "$value" != "not found" ]]; then
        printf "  ${C_GREEN}✔${C_RESET}  %-25s %s\n" "$label" "$value"
    else
        printf "  ${C_DIM}✗${C_RESET}  %-25s %s\n" "$label" "non installé"
    fi
}

run_full_check() {
    log_section "Statut des outils installés"
    print_check_row "Node.js"        "$(check_node)"
    print_check_row "npm"            "$(check_npm)"
    print_check_row "Python 3"       "$(check_python)"
    print_check_row "PHP"            "$(check_php)"
    print_check_row "Go"             "$(check_go)"
    print_check_row "Rust"           "$(check_rust)"
    print_check_row "Docker"         "$(check_docker)"
    print_check_row "Docker Compose" "$(check_docker_compose)"
    print_check_row "PostgreSQL"     "$(check_postgres)"
    print_check_row "Redis"          "$(check_redis)"
    print_check_row "Nginx"          "$(check_nginx)"
    print_check_row "git"            "$(check_command_version git --version 2>/dev/null | awk '{print $3}' || echo '')"
    print_check_row "tmux"           "$(check_command_version tmux -V 2>/dev/null | awk '{print $2}' || echo '')"
    print_check_row "fzf"            "$(check_command_version fzf --version 2>/dev/null | awk '{print $1}' || echo '')"
    print_check_row "ripgrep (rg)"   "$(check_command_version rg --version 2>/dev/null | head -1 | awk '{print $2}' || echo '')"
    echo
}
