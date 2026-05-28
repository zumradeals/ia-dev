#!/usr/bin/env bash
# bootstrap/30-users-groups.sh — Création utilisateur devuser et groupe devlab
# Idempotent : ne recrée pas l'utilisateur s'il existe

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

DEVLAB_USER="${DEVLAB_USER:-devuser}"
DEVLAB_GROUP="${DEVLAB_GROUP:-devlab}"

# ── Groupe devlab ─────────────────────────────
log_info "Groupe : ${DEVLAB_GROUP}"
if check_group_exists "$DEVLAB_GROUP"; then
    log_skip "Groupe '${DEVLAB_GROUP}' existe déjà"
else
    groupadd "$DEVLAB_GROUP"
    log_ok "Groupe '${DEVLAB_GROUP}' créé"
fi

# ── Utilisateur devuser ───────────────────────
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

# ── Groupes supplémentaires ───────────────────
log_info "Attribution des groupes..."
EXTRA_GROUPS=("sudo" "docker" "www-data")
for group in "${EXTRA_GROUPS[@]}"; do
    if check_group_exists "$group"; then
        if ! id -nG "$DEVLAB_USER" | grep -qw "$group"; then
            usermod -aG "$group" "$DEVLAB_USER"
            log_step "${DEVLAB_USER} ajouté au groupe ${group}"
        else
            log_skip "${DEVLAB_USER} déjà dans le groupe ${group}"
        fi
    else
        log_debug "Groupe ${group} absent — ignoré (sera créé par le module concerné)"
    fi
done

# ── Sudo sans mot de passe ────────────────────
SUDOERS_FILE="/etc/sudoers.d/devlab"
if [[ ! -f "$SUDOERS_FILE" ]]; then
    echo "${DEVLAB_USER} ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
    log_ok "Sudo sans mot de passe configuré pour ${DEVLAB_USER}"
else
    log_skip "Sudoers devlab déjà configuré"
fi

# ── Répertoire .ssh ───────────────────────────
USER_HOME=$(getent passwd "$DEVLAB_USER" | cut -d: -f6)
SSH_DIR="${USER_HOME}/.ssh"

if [[ ! -d "$SSH_DIR" ]]; then
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    chown "${DEVLAB_USER}:${DEVLAB_GROUP}" "$SSH_DIR"
    log_ok "Répertoire .ssh créé : ${SSH_DIR}"
else
    log_skip "Répertoire .ssh existant : ${SSH_DIR}"
fi

# ── Authorized_keys (si clé root présente) ───
ROOT_KEYS="/root/.ssh/authorized_keys"
USER_KEYS="${SSH_DIR}/authorized_keys"

if [[ -f "$ROOT_KEYS" && ! -f "$USER_KEYS" ]]; then
    cp "$ROOT_KEYS" "$USER_KEYS"
    chmod 600 "$USER_KEYS"
    chown "${DEVLAB_USER}:${DEVLAB_GROUP}" "$USER_KEYS"
    log_ok "Clés SSH copiées depuis root vers ${DEVLAB_USER}"
fi

# ── Mot de passe devuser ──────────────────────
# Définit un mot de passe si DEVLAB_USER_PASSWORD est défini dans secrets.env
# Sinon déverrouille le compte pour permettre su depuis root sans mot de passe
if [[ -n "${DEVLAB_USER_PASSWORD:-}" ]]; then
    echo "${DEVLAB_USER}:${DEVLAB_USER_PASSWORD}" | chpasswd
    log_ok "Mot de passe ${DEVLAB_USER} défini depuis DEVLAB_USER_PASSWORD"
else
    # Déverrouille le compte (passwd -u) sans définir de mot de passe
    # Permet à root de faire 'su - devuser' sans saisie
    passwd -u "$DEVLAB_USER" 2>/dev/null || true
    log_info "Mot de passe ${DEVLAB_USER} non défini — utilisez 'passwd ${DEVLAB_USER}' pour en créer un"
    log_info "  ou définissez DEVLAB_USER_PASSWORD dans config/secrets.env"
fi

state_set "bootstrap.users-groups" "$(date +%Y%m%d)" "installed"
log_ok "Utilisateurs et groupes configurés"
echo
log_info "Utilisateur : ${DEVLAB_USER}  |  Groupe principal : ${DEVLAB_GROUP}  |  Home : ${USER_HOME}"
