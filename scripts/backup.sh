#!/usr/bin/env bash
# scripts/backup.sh — Sauvegarde des configurations système DevLab

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="backup"

# shellcheck source=../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "backup" "maintenance"
log_section "Sauvegarde DevLab"

TS=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${DEVLAB_ROOT}/backups/configs/${TS}"
mkdir -p "$BACKUP_DIR"

backup_config_file() {
    local src="$1"
    local label="${2:-$(basename "$src")}"
    if [[ -f "$src" ]]; then
        cp "$src" "${BACKUP_DIR}/${label}"
        log_step "${label} sauvegardé"
    else
        log_debug "${src} absent — ignoré"
    fi
}

# ─── Configs système ──────────────────────────
log_info "Sauvegarde des configurations..."
backup_config_file "/etc/nginx/nginx.conf" "nginx.conf"
backup_config_file "/etc/nginx/conf.d/devlab-default.conf" "nginx-devlab.conf"
backup_config_file "/etc/redis/redis.conf" "redis.conf"
backup_config_file "/etc/ssh/sshd_config" "sshd_config"
backup_config_file "/etc/fail2ban/jail.local" "fail2ban-jail.local"
backup_config_file "/etc/docker/daemon.json" "docker-daemon.json"

# ─── Registre d'état ──────────────────────────
backup_config_file "${DEVLAB_ROOT}/state/registry.json" "devlab-registry.json"
backup_config_file "${DEVLAB_ROOT}/config/default.env" "default.env"
backup_config_file "${DEVLAB_ROOT}/config/modules.conf" "modules.conf"

# ─── Dump PostgreSQL ─────────────────────────
if command -v pg_dumpall &>/dev/null && systemctl is-active --quiet postgresql 2>/dev/null; then
    log_info "Dump PostgreSQL..."
    mkdir -p "${DEVLAB_ROOT}/backups/databases"
    local pg_dump_file="${DEVLAB_ROOT}/backups/databases/${TS}_postgresql.sql.gz"
    sudo -u postgres pg_dumpall 2>/dev/null | gzip > "$pg_dump_file"
    log_ok "Dump PostgreSQL : $(basename "$pg_dump_file")"
fi

# ─── Archive finale ───────────────────────────
local archive="${DEVLAB_ROOT}/backups/configs/devlab-backup-${TS}.tar.gz"
tar -czf "$archive" -C "${DEVLAB_ROOT}/backups/configs" "$TS" 2>/dev/null
rm -rf "$BACKUP_DIR"

log_ok "Backup créé : ${archive}"
log_info "Taille : $(du -sh "$archive" | awk '{print $1}')"

# ─── Rotation (garder 10 derniers) ────────────
local backup_count; backup_count=$(find "${DEVLAB_ROOT}/backups/configs" -name "*.tar.gz" | wc -l)
if [[ "$backup_count" -gt 10 ]]; then
    find "${DEVLAB_ROOT}/backups/configs" -name "*.tar.gz" | \
        sort | head -n $(( backup_count - 10 )) | xargs rm -f
    log_info "Rotation : anciens backups supprimés (max 10 conservés)"
fi
