#!/usr/bin/env bash
# setup.sh — Point d'entrée pour le premier lancement DevLab
#
# Usage (depuis le répertoire cloné) :
#   sudo bash setup.sh
#
# Ce script :
#   1. Détecte automatiquement DEVLAB_ROOT depuis son emplacement
#   2. Crée un lien symbolique devlab → /usr/local/bin/devlab
#   3. Configure DEVLAB_ROOT dans l'environnement
#   4. Lance le bootstrap complet

set -euo pipefail

# ─── Auto-détection ──────────────────────────
DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DEVLAB_ROOT

# ─── Vérifications ───────────────────────────
if [[ "$(id -u)" -ne 0 ]]; then
    echo "[ERREUR] setup.sh doit être exécuté en root : sudo bash setup.sh"
    exit 1
fi

echo ""
echo "  DevLab Bootstrap Setup"
echo "  ─────────────────────────────────────"
echo "  DEVLAB_ROOT = ${DEVLAB_ROOT}"
echo ""

# ─── Symlink devlab dans PATH ─────────────────
DEVLAB_BIN="${DEVLAB_ROOT}/bin/devlab"

if [[ ! -f "$DEVLAB_BIN" ]]; then
    echo "[ERREUR] bin/devlab introuvable dans ${DEVLAB_ROOT}"
    echo "  Êtes-vous bien dans le répertoire du dépôt ?"
    exit 1
fi

chmod +x "$DEVLAB_BIN"

if [[ -L "/usr/local/bin/devlab" ]]; then
    # Mettre à jour le lien si le chemin a changé
    current_target=$(readlink /usr/local/bin/devlab)
    if [[ "$current_target" != "$DEVLAB_BIN" ]]; then
        ln -sf "$DEVLAB_BIN" /usr/local/bin/devlab
        echo "  [OK] Lien mis à jour : /usr/local/bin/devlab → ${DEVLAB_BIN}"
    else
        echo "  [OK] Lien déjà en place : /usr/local/bin/devlab"
    fi
elif [[ -f "/usr/local/bin/devlab" ]]; then
    echo "  [WARN] /usr/local/bin/devlab existe et n'est pas un lien — conservé"
else
    ln -sf "$DEVLAB_BIN" /usr/local/bin/devlab
    echo "  [OK] Lien créé : /usr/local/bin/devlab → ${DEVLAB_BIN}"
fi

# ─── profile.d pour DEVLAB_ROOT persistant ────
PROFILE_D="/etc/profile.d/devlab.sh"
if [[ ! -f "$PROFILE_D" ]]; then
    cat > "$PROFILE_D" << PROFILE
# DevLab — Variables d'environnement système
export DEVLAB_ROOT="${DEVLAB_ROOT}"
export PATH="\${DEVLAB_ROOT}/bin:\${PATH}"
PROFILE
    echo "  [OK] Variables d'environnement : ${PROFILE_D}"
else
    # Mettre à jour DEVLAB_ROOT si changé
    if ! grep -q "DEVLAB_ROOT=\"${DEVLAB_ROOT}\"" "$PROFILE_D"; then
        sed -i "s|DEVLAB_ROOT=.*|DEVLAB_ROOT=\"${DEVLAB_ROOT}\"|" "$PROFILE_D"
        echo "  [OK] DEVLAB_ROOT mis à jour dans ${PROFILE_D}"
    else
        echo "  [OK] profile.d déjà configuré"
    fi
fi

echo ""
echo "  Lancement du bootstrap..."
echo "  ─────────────────────────────────────"
echo ""

# ─── Bootstrap complet ────────────────────────
exec bash "$DEVLAB_BIN" bootstrap
