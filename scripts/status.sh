#!/usr/bin/env bash
# scripts/status.sh — Vue d'ensemble rapide de l'état DevLab

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="status"

# shellcheck source=../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"
# shellcheck source=../lib/checks.sh
source "${DEVLAB_ROOT}/lib/checks.sh"

log_init "status" "maintenance"
devlab_banner

log_section "État DevLab"
printf "  Hôte    : %s\n" "$(hostname)"
printf "  Date    : %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
printf "  Root    : %s\n" "${DEVLAB_ROOT}"
printf "  User    : %s\n" "${DEVLAB_USER:-devuser}"
echo

run_full_check

log_section "Registre des modules"
state_list 2>/dev/null | while IFS=$'\t' read -r key status version installed_at; do
    local color
    case "$status" in
        installed) color="$C_GREEN" ;;
        failed)    color="$C_RED" ;;
        *)         color="$C_DIM" ;;
    esac
    printf "  ${color}%-12s${C_RESET} %-35s %s\n" "$status" "$key" "${version:-}"
done

echo
log_info "Pour plus de détails : devlab health"
