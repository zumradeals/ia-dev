#!/usr/bin/env bash
# bootstrap/00-preflight.sh — Vérifications pré-requises (lecture seule, non destructif)
# Ce script ne modifie rien. Il valide que le système est prêt.

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVLAB_ROOT
DEVLAB_MODULE="preflight"

# shellcheck source=../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../lib/checks.sh
source "${DEVLAB_ROOT}/lib/checks.sh"

log_init "preflight" "bootstrap"
log_section "Vérifications pré-requises"

ERRORS=0

# ── Système d'exploitation ────────────────────
log_info "Vérification OS..."
if [[ ! -f /etc/os-release ]]; then
    log_error "Impossible de détecter l'OS (/etc/os-release absent)"
    (( ERRORS++ )) || true
else
    # shellcheck source=/dev/null
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        log_error "OS non supporté : ${ID}. Ubuntu requis."
        (( ERRORS++ )) || true
    else
        log_ok "OS : ${PRETTY_NAME}"
        if [[ "$VERSION_ID" != "24.04" ]]; then
            log_warn "Version non testée : ${VERSION_ID} (testé sur 24.04 LTS)"
        fi
    fi
fi

# ── Architecture ──────────────────────────────
log_info "Vérification architecture..."
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        log_ok "Architecture : ${ARCH}" ;;
    aarch64|arm64)
        log_warn "Architecture ARM64 : certains outils binaires peuvent manquer" ;;
    *)
        log_error "Architecture non supportée : ${ARCH}"
        (( ERRORS++ )) || true ;;
esac

# ── Privilèges ────────────────────────────────
log_info "Vérification privilèges..."
if [[ "$(id -u)" -ne 0 ]]; then
    log_error "Le bootstrap doit être exécuté en root (sudo devlab bootstrap)"
    (( ERRORS++ )) || true
else
    log_ok "Exécution en root"
fi

# ── Espace disque ─────────────────────────────
log_info "Vérification espace disque..."
AVAILABLE_KB=$(df / --output=avail 2>/dev/null | tail -1)
AVAILABLE_GB=$(( AVAILABLE_KB / 1024 / 1024 ))
MIN_GB=10

if [[ "$AVAILABLE_GB" -lt "$MIN_GB" ]]; then
    log_error "Espace insuffisant : ${AVAILABLE_GB}GB disponible (minimum : ${MIN_GB}GB)"
    (( ERRORS++ )) || true
else
    log_ok "Espace disque : ${AVAILABLE_GB}GB disponible"
fi

# ── RAM ───────────────────────────────────────
log_info "Vérification RAM..."
TOTAL_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
MIN_MB=512

if [[ "$TOTAL_MB" -lt "$MIN_MB" ]]; then
    log_warn "RAM faible : ${TOTAL_MB}MB (recommandé : 1024MB minimum)"
else
    log_ok "RAM : ${TOTAL_MB}MB"
fi

# ── Connectivité réseau ───────────────────────
log_info "Vérification connectivité réseau..."
if curl -fsS --max-time 10 --connect-timeout 5 https://archive.ubuntu.com > /dev/null 2>&1; then
    log_ok "Connectivité : archive.ubuntu.com accessible"
else
    log_error "Pas de connectivité vers archive.ubuntu.com"
    (( ERRORS++ )) || true
fi

# ── Commandes requises ───────────────────────
log_info "Vérification commandes de base..."
REQUIRED_CMDS=("curl" "bash" "grep" "awk" "sed")
for cmd in "${REQUIRED_CMDS[@]}"; do
    if command_exists "$cmd"; then
        log_step "${cmd} : disponible"
    else
        log_error "Commande requise absente : ${cmd}"
        (( ERRORS++ )) || true
    fi
done

# ── jq (pour le registre d'état) ─────────────
if ! command_exists jq; then
    log_warn "jq absent — sera installé durant le bootstrap (base-packages)"
fi

# ── Résultat final ────────────────────────────
echo
if [[ "$ERRORS" -gt 0 ]]; then
    log_fatal "Preflight échoué : ${ERRORS} erreur(s). Corrigez les problèmes ci-dessus avant de continuer."
else
    log_ok "Preflight : toutes les vérifications passées"
fi
