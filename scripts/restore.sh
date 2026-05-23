#!/usr/bin/env bash
# scripts/restore.sh — Restauration depuis un backup DevLab

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="restore"

# shellcheck source=../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

require_root
log_init "restore" "maintenance"
log_section "Restauration DevLab"

BACKUP_DIR="${DEVLAB_ROOT}/backups/configs"
BACKUP_ID="${1:-}"

if [[ -z "$BACKUP_ID" ]]; then
    log_info "Backups disponibles :"
    ls -lt "$BACKUP_DIR"/*.tar.gz 2>/dev/null | awk '{print "  " $NF}' || log_warn "Aucun backup trouvé"
    echo
    log_fatal "Usage : devlab restore <backup_id>
Exemple : devlab restore devlab-backup-20260523_143022.tar.gz"
fi

BACKUP_FILE="${BACKUP_DIR}/${BACKUP_ID}"
[[ ! -f "$BACKUP_FILE" ]] && BACKUP_FILE="$BACKUP_ID"
[[ ! -f "$BACKUP_FILE" ]] && log_fatal "Backup non trouvé : ${BACKUP_ID}"

log_warn "Restauration depuis : $(basename "$BACKUP_FILE")"
log_warn "Cette opération peut écraser des configurations système."

if ! confirm "Continuer la restauration ?"; then
    log_info "Restauration annulée"
    exit 0
fi

TMP_DIR=$(mktemp -d)
tar -xzf "$BACKUP_FILE" -C "$TMP_DIR"
EXTRACT_DIR=$(ls "$TMP_DIR")
RESTORE_SRC="${TMP_DIR}/${EXTRACT_DIR}"

restore_if_exists() {
    local src="$1"
    local dest="$2"
    if [[ -f "${RESTORE_SRC}/${src}" ]]; then
        backup_file "$dest"
        cp "${RESTORE_SRC}/${src}" "$dest"
        log_step "Restauré : ${dest}"
    fi
}

restore_if_exists "nginx.conf" "/etc/nginx/nginx.conf"
restore_if_exists "redis.conf" "/etc/redis/redis.conf"
restore_if_exists "sshd_config" "/etc/ssh/sshd_config"
restore_if_exists "fail2ban-jail.local" "/etc/fail2ban/jail.local"
restore_if_exists "docker-daemon.json" "/etc/docker/daemon.json"
restore_if_exists "devlab-registry.json" "${DEVLAB_ROOT}/state/registry.json"

rm -rf "$TMP_DIR"

# Rechargement des services
systemctl reload nginx 2>/dev/null || true
systemctl restart redis-server 2>/dev/null || true
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true

log_ok "Restauration terminée depuis $(basename "$BACKUP_FILE")"
