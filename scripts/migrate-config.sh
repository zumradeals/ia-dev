#!/usr/bin/env bash
# scripts/migrate-config.sh — Corrections des valeurs obsolètes dans config/local.env
# Appelé automatiquement par update.sh. Peut aussi être lancé manuellement.

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="migrate-config"

# shellcheck source=../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"

LOCAL_ENV="${DEVLAB_ROOT}/config/local.env"

if [[ ! -f "$LOCAL_ENV" ]]; then
    log_warn "config/local.env introuvable — rien à migrer"
    exit 0
fi

log_section "Migration config/local.env"

CHANGED=0

_fix() {
    local key="$1" old_val="$2" new_val="$3"
    if grep -q "^${key}=\"${old_val}\"" "$LOCAL_ENV" 2>/dev/null; then
        sed -i "s|^${key}=\"${old_val}\"|${key}=\"${new_val}\"|" "$LOCAL_ENV"
        log_ok "${key} : \"${old_val}\" → \"${new_val}\""
        CHANGED=1
    fi
}

_ensure() {
    local key="$1" val="$2"
    if ! grep -q "^${key}=" "$LOCAL_ENV" 2>/dev/null; then
        echo "${key}=\"${val}\"" >> "$LOCAL_ENV"
        log_ok "${key} ajouté : \"${val}\""
        CHANGED=1
    fi
}

# ── Migrations ────────────────────────────────────────────────────────────────

# v1 → v2 : renommage du namespace Docker Hub gamad/ → zumradeals/
_fix "WORKSPACE_IMAGE" "gamad/gamadcode-workspace:latest" "zumradeals/gamadcode-workspace:latest"

# Valeur manquante dans les installations antérieures à 2026-05-31
_ensure "WORKSPACE_IMAGE" "zumradeals/gamadcode-workspace:latest"

# ─────────────────────────────────────────────────────────────────────────────

if [[ "$CHANGED" -eq 0 ]]; then
    log_ok "Aucune migration nécessaire"
fi
