#!/usr/bin/env bash
# scripts/health.sh — Diagnostic de santé complet du système DevLab

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="health"

# shellcheck source=../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../lib/checks.sh
source "${DEVLAB_ROOT}/lib/checks.sh"
# shellcheck source=../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "health" "maintenance"
devlab_banner

echo
log_section "Diagnostic de santé DevLab"
ISSUES=0

# ─── Outils installés ─────────────────────────
run_full_check

# ─── Services système ─────────────────────────
log_section "État des services"
declare -A services=(
    ["nginx"]="Web server"
    ["postgresql"]="PostgreSQL"
    ["redis-server"]="Redis"
    ["docker"]="Docker"
    ["fail2ban"]="Fail2ban"
    ["ssh"]="SSH"
)

for svc in "${!services[@]}"; do
    label="${services[$svc]}"
    if check_service_running "$svc"; then
        printf "  ${C_GREEN}●${C_RESET} %-20s ${C_GREEN}actif${C_RESET}\n" "$label"
    elif check_service_running "${svc}d"; then
        printf "  ${C_GREEN}●${C_RESET} %-20s ${C_GREEN}actif${C_RESET}\n" "$label"
    else
        printf "  ${C_RED}●${C_RESET} %-20s ${C_RED}inactif${C_RESET}\n" "$label"
        (( ISSUES++ )) || true
    fi
done

# ─── Ports ouverts ────────────────────────────
log_section "Ports en écoute"
declare -A ports=(
    ["22"]="SSH"
    ["80"]="HTTP"
    ["5432"]="PostgreSQL"
    ["6379"]="Redis"
    ["8080"]="code-server"
)

for port in "${!ports[@]}"; do
    label="${ports[$port]}"
    if check_port_open "$port"; then
        printf "  ${C_GREEN}✔${C_RESET}  %-8s %s\n" ":${port}" "$label"
    else
        printf "  ${C_DIM}✗${C_RESET}  %-8s %s (non actif)\n" ":${port}" "$label"
    fi
done

# ─── Espace disque ────────────────────────────
log_section "Ressources système"
echo "  Espace disque :"
df -h / "${DEVLAB_ROOT}" 2>/dev/null | awk 'NR>1 {printf "    %-20s %s utilisé (%s disponible)\n", $6, $5, $4}'
echo
echo "  Mémoire :"
free -h | awk '/Mem:/ {printf "    RAM : %s total, %s utilisé, %s libre\n", $2, $3, $4}'
free -h | awk '/Swap:/ {printf "    Swap: %s total, %s utilisé\n", $2, $3}'
echo
echo "  Charge CPU :"
uptime | awk '{print "    " $0}'

# ─── Docker ───────────────────────────────────
if command_exists docker && docker info &>/dev/null; then
    log_section "Docker"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
fi

# ─── Sécurité UFW ─────────────────────────────
log_section "Pare-feu UFW"
if command_exists ufw; then
    ufw status 2>/dev/null | head -20 || log_warn "UFW non accessible"
fi

# ─── Résumé ───────────────────────────────────
echo
if [[ "$ISSUES" -eq 0 ]]; then
    log_ok "Système sain — aucun problème détecté"
else
    log_warn "${ISSUES} service(s) inactif(s) détecté(s)"
fi
