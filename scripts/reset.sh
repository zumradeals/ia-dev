#!/usr/bin/env bash
# scripts/reset.sh — Réinitialisation sélective d'un module dans le registre
# NE désinstalle PAS les logiciels — retire uniquement l'entrée du registre

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="reset"

# shellcheck source=../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "reset" "maintenance"

MODULE="${1:-}"

if [[ -z "$MODULE" ]]; then
    log_fatal "Usage : devlab reset <module_key>
Exemple : devlab reset languages/nodejs
Note : retire l'entrée du registre — ne désinstalle pas le logiciel"
fi

if ! state_is_installed "$MODULE"; then
    log_warn "Module '${MODULE}' non trouvé dans le registre"
    exit 0
fi

log_warn "Cette opération retire '${MODULE}' du registre."
log_warn "Le logiciel reste installé sur le système."
log_info "Pour réinstaller ensuite : devlab install ${MODULE}"
echo

if confirm "Retirer '${MODULE}' du registre ?"; then
    state_remove "$MODULE"
    log_ok "Module '${MODULE}' retiré du registre"
    log_info "Relancez 'devlab install ${MODULE}' pour le réinstaller"
else
    log_info "Opération annulée"
fi
