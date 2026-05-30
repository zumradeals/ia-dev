#!/usr/bin/env bash
# bootstrap/30-users-groups.sh — Groupe devlab + utilisateur de travail
# Si DEVLAB_USER=root (défaut), aucun utilisateur créé — root est l'opérateur.
# Idempotent.

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="users-groups"

# shellcheck source=../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../lib/checks.sh
source "${DEVLAB_ROOT}/lib/checks.sh"
# shellcheck source=../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

require_root
log_init "users-groups" "bootstrap"
log_section "Gestion utilisateurs et groupes"

DEVLAB_USER="${DEVLAB_USER:-root}"
DEVLAB_GROUP="${DEVLAB_GROUP:-devlab}"

# ── Groupe devlab (pour les services système) ──
log_info "Groupe : ${DEVLAB_GROUP}"
if check_group_exists "$DEVLAB_GROUP"; then
    log_skip "Groupe '${DEVLAB_GROUP}' existe déjà"
else
    groupadd "$DEVLAB_GROUP"
    log_ok "Groupe '${DEVLAB_GROUP}' créé"
fi

# ── Utilisateur de travail ────────────────────
if [[ "$DEVLAB_USER" == "root" ]]; then
    log_info "DEVLAB_USER=root — aucun utilisateur supplémentaire créé"
    log_info "Root est l'opérateur principal du DevLab"
else
    log_info "Utilisateur : ${DEVLAB_USER}"
    if check_user_exists "$DEVLAB_USER"; then
        log_skip "Utilisateur '${DEVLAB_USER}' existe déjà"
    else
        useradd \
            --gid "$DEVLAB_GROUP" \
            --groups "sudo,docker" \
            --create-home \
            --shell /bin/bash \
            --comment "DevLab Development User" \
            "$DEVLAB_USER" 2>/dev/null || \
        useradd \
            --gid "$DEVLAB_GROUP" \
            --create-home \
            --shell /bin/bash \
            --comment "DevLab Development User" \
            "$DEVLAB_USER"
        log_ok "Utilisateur '${DEVLAB_USER}' créé"
    fi

    # Groupes supplémentaires
    for group in sudo docker www-data; do
        if check_group_exists "$group"; then
            if ! id -nG "$DEVLAB_USER" | grep -qw "$group"; then
                usermod -aG "$group" "$DEVLAB_USER"
                log_step "${DEVLAB_USER} ajouté au groupe ${group}"
            else
                log_skip "${DEVLAB_USER} déjà dans le groupe ${group}"
            fi
        fi
    done

    # Sudo sans mot de passe
    SUDOERS_FILE="/etc/sudoers.d/devlab"
    if [[ ! -f "$SUDOERS_FILE" ]]; then
        echo "${DEVLAB_USER} ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
        chmod 440 "$SUDOERS_FILE"
        log_ok "Sudo sans mot de passe configuré pour ${DEVLAB_USER}"
    else
        log_skip "Sudoers devlab déjà configuré"
    fi

    # Mot de passe
    if [[ -n "${DEVLAB_USER_PASSWORD:-}" ]]; then
        echo "${DEVLAB_USER}:${DEVLAB_USER_PASSWORD}" | chpasswd
        log_ok "Mot de passe ${DEVLAB_USER} défini"
    else
        passwd -u "$DEVLAB_USER" 2>/dev/null || true
        log_info "Mot de passe ${DEVLAB_USER} non défini — définissez DEVLAB_USER_PASSWORD dans secrets.env"
    fi
fi

# ── Répertoire .ssh de l'opérateur ───────────
USER_HOME=$(getent passwd "$DEVLAB_USER" | cut -d: -f6)
SSH_DIR="${USER_HOME}/.ssh"

if [[ ! -d "$SSH_DIR" ]]; then
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    log_ok "Répertoire .ssh créé : ${SSH_DIR}"
else
    log_skip "Répertoire .ssh existant : ${SSH_DIR}"
fi

state_set "bootstrap.users-groups" "$(date +%Y%m%d)" "installed"
log_ok "Utilisateurs et groupes configurés"
echo
log_info "Opérateur : ${DEVLAB_USER}  |  Home : ${USER_HOME}"
