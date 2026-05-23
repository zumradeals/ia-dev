#!/usr/bin/env bash
# lib/state.sh — Gestion du registre d'état des modules installés
# Source de vérité : state/registry.json

# Requiert lib/core.sh déjà sourcé

REGISTRY_FILE="${DEVLAB_ROOT}/state/registry.json"

# ─────────────────────────────────────────────
# INITIALISATION DU REGISTRE
# ─────────────────────────────────────────────
state_init() {
    local registry_dir; registry_dir="$(dirname "$REGISTRY_FILE")"
    mkdir -p "$registry_dir"

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local host; host=$(hostname -f 2>/dev/null || hostname)
        cat > "$REGISTRY_FILE" << EOF
{
  "_meta": {
    "version": "1.0",
    "created": "${ts}",
    "updated": "${ts}",
    "devlab_version": "1.0.0",
    "host": "${host}"
  },
  "modules": {}
}
EOF
        log_debug "Registre initialisé : ${REGISTRY_FILE}"
    fi
}

_registry_require_jq() {
    command_exists jq || log_fatal "jq est requis pour la gestion du registre. Lancez d'abord le bootstrap."
}

# ─────────────────────────────────────────────
# LECTURE
# ─────────────────────────────────────────────
state_is_installed() {
    # Usage: state_is_installed <module_key>
    # Retourne 0 si installé avec succès, 1 sinon
    local key="$1"
    _registry_require_jq
    state_init

    local status
    status=$(jq -r --arg k "$key" '.modules[$k].status // "none"' "$REGISTRY_FILE")
    [[ "$status" == "installed" ]]
}

state_get_version() {
    # Usage: state_get_version <module_key>
    # Retourne la version installée ou chaîne vide
    local key="$1"
    _registry_require_jq
    state_init
    jq -r --arg k "$key" '.modules[$k].version // ""' "$REGISTRY_FILE"
}

state_get_field() {
    # Usage: state_get_field <module_key> <field>
    local key="$1"
    local field="$2"
    _registry_require_jq
    state_init
    jq -r --arg k "$key" --arg f "$field" '.modules[$k][$f] // ""' "$REGISTRY_FILE"
}

state_list() {
    _registry_require_jq
    state_init
    jq -r '.modules | to_entries[] | "\(.key)\t\(.value.status)\t\(.value.version // "-")\t\(.value.installed_at // "-")"' "$REGISTRY_FILE"
}

# ─────────────────────────────────────────────
# ÉCRITURE
# ─────────────────────────────────────────────
state_set() {
    # Usage: state_set <module_key> <version> <status> [extra_json_field=value...]
    # status : installed | failed | skipped
    local key="$1"
    local version="$2"
    local status="$3"
    _registry_require_jq
    state_init

    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local tmp; tmp=$(mktemp)

    jq --arg k "$key" \
       --arg v "$version" \
       --arg s "$status" \
       --arg t "$ts" \
       '.modules[$k] = {
          "status": $s,
          "version": $v,
          "installed_at": $t
        } | ._meta.updated = $t' \
       "$REGISTRY_FILE" > "$tmp" && mv "$tmp" "$REGISTRY_FILE"

    log_debug "Registre mis à jour : ${key} → ${status} (${version})"
}

state_set_failed() {
    local key="$1"
    local reason="${2:-unknown error}"
    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local tmp; tmp=$(mktemp)

    _registry_require_jq
    state_init

    jq --arg k "$key" \
       --arg r "$reason" \
       --arg t "$ts" \
       '.modules[$k] = {
          "status": "failed",
          "version": "",
          "installed_at": $t,
          "error": $r
        } | ._meta.updated = $t' \
       "$REGISTRY_FILE" > "$tmp" && mv "$tmp" "$REGISTRY_FILE"
}

state_remove() {
    # Retire un module du registre (pour réinstallation)
    local key="$1"
    _registry_require_jq
    state_init
    local tmp; tmp=$(mktemp)
    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg k "$key" --arg t "$ts" \
       'del(.modules[$k]) | ._meta.updated = $t' \
       "$REGISTRY_FILE" > "$tmp" && mv "$tmp" "$REGISTRY_FILE"
    log_info "Module retiré du registre : ${key}"
}

# ─────────────────────────────────────────────
# HELPER POUR INSTALLERS
# ─────────────────────────────────────────────
installer_run() {
    # Wrapper idempotent pour tout installer
    # Usage: installer_run <module_key> <label> <version_cmd> <install_fn>
    local key="$1"
    local label="$2"
    local version_cmd="$3"
    local install_fn="$4"

    if state_is_installed "$key"; then
        local installed_ver; installed_ver=$(state_get_version "$key")
        log_skip "${label} déjà installé (${installed_ver})"
        return 0
    fi

    log_info "Installation : ${label}"

    if [[ "${DEVLAB_DRY_RUN:-false}" == "true" ]]; then
        log_skip "[DRY-RUN] ${label} — simulation"
        state_set "$key" "dry-run" "skipped"
        return 0
    fi

    local exit_code=0
    "$install_fn" || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        local version
        version=$(eval "$version_cmd" 2>/dev/null || echo "unknown")
        state_set "$key" "$version" "installed"
        log_ok "${label} installé avec succès (${version})"
    else
        state_set_failed "$key" "exit code ${exit_code}"
        log_error "${label} — échec (code ${exit_code})"
        return $exit_code
    fi
}
