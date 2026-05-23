#!/usr/bin/env bash
# lib/packages.sh — Wrappers idempotents pour les gestionnaires de paquets
# Requiert lib/core.sh déjà sourcé

# ─────────────────────────────────────────────
# APT
# ─────────────────────────────────────────────
apt_update() {
    log_step "Mise à jour de l'index APT"
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
}

apt_install() {
    # Installe un ou plusieurs paquets APT, uniquement si absents
    # Usage: apt_install pkg1 pkg2 pkg3
    local to_install=()

    for pkg in "$@"; do
        if check_apt_package "$pkg"; then
            log_debug "APT : ${pkg} déjà installé"
        else
            to_install+=("$pkg")
        fi
    done

    if [[ ${#to_install[@]} -eq 0 ]]; then
        log_skip "APT : tous les paquets déjà présents ($*)"
        return 0
    fi

    log_step "APT install : ${to_install[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${to_install[@]}"
}

apt_remove() {
    local pkg="$1"
    if check_apt_package "$pkg"; then
        DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq "$pkg"
        log_ok "APT : ${pkg} désinstallé"
    else
        log_skip "APT : ${pkg} n'était pas installé"
    fi
}

apt_repo_add() {
    # Ajoute un dépôt APT de façon idempotente
    # Usage: apt_repo_add <name> <repo_line> <gpg_url> <gpg_keyfile>
    local name="$1"
    local repo_line="$2"
    local gpg_url="$3"
    local keyfile="/etc/apt/keyrings/${name}.gpg"
    local list_file="/etc/apt/sources.list.d/${name}.list"

    mkdir -p /etc/apt/keyrings

    if [[ ! -f "$keyfile" ]]; then
        log_step "Ajout clé GPG : ${name}"
        curl -fsSL "$gpg_url" | gpg --dearmor -o "$keyfile"
        chmod a+r "$keyfile"
    else
        log_debug "Clé GPG déjà présente : ${keyfile}"
    fi

    if [[ ! -f "$list_file" ]]; then
        log_step "Ajout dépôt APT : ${name}"
        echo "$repo_line" > "$list_file"
        apt_update
    else
        log_debug "Dépôt APT déjà configuré : ${list_file}"
    fi
}

# ─────────────────────────────────────────────
# NPM / NODE
# ─────────────────────────────────────────────
npm_global_install() {
    # Usage: npm_global_install <package> [expected_cmd]
    local pkg="$1"
    local check_cmd="${2:-$1}"

    if command_exists "$check_cmd"; then
        log_skip "npm global : ${pkg} déjà installé (${check_cmd} disponible)"
        return 0
    fi

    log_step "npm install -g ${pkg}"
    npm install -g "$pkg" --quiet
}

pnpm_global_install() {
    local pkg="$1"
    local check_cmd="${2:-$1}"

    if command_exists "$check_cmd"; then
        log_skip "pnpm global : ${pkg} déjà installé"
        return 0
    fi

    log_step "pnpm add -g ${pkg}"
    pnpm add -g "$pkg"
}

# ─────────────────────────────────────────────
# PIP / PYTHON
# ─────────────────────────────────────────────
pip_install() {
    # Usage: pip_install <package> [check_cmd]
    local pkg="$1"
    local check_cmd="${2:-$1}"

    if command_exists "$check_cmd"; then
        log_skip "pip : ${pkg} déjà installé"
        return 0
    fi

    log_step "pip install ${pkg}"
    pip3 install --quiet --user "$pkg"
}

# ─────────────────────────────────────────────
# CARGO / RUST
# ─────────────────────────────────────────────
cargo_install() {
    local pkg="$1"
    local check_cmd="${2:-$1}"

    if command_exists "$check_cmd"; then
        log_skip "cargo : ${pkg} déjà installé"
        return 0
    fi

    log_step "cargo install ${pkg}"
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env" 2>/dev/null || true
    cargo install "$pkg" --quiet
}

# ─────────────────────────────────────────────
# TÉLÉCHARGEMENT SÉCURISÉ
# ─────────────────────────────────────────────
safe_download() {
    # Usage: safe_download <url> <output_path>
    local url="$1"
    local output="$2"

    log_step "Téléchargement : $(basename "$output")"
    curl -fsSL --retry 3 --retry-delay 2 \
         --connect-timeout 30 --max-time 300 \
         -o "$output" "$url" || log_fatal "Échec téléchargement : ${url}"
}

safe_download_pipe() {
    # Usage: safe_download_pipe <url> | cmd
    local url="$1"
    curl -fsSL --retry 3 --retry-delay 2 \
         --connect-timeout 30 --max-time 300 \
         "$url"
}
