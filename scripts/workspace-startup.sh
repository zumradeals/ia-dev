#!/usr/bin/env bash
# Exécuté via ENTRYPOINTD avant le démarrage de code-server.
# Ne pas ajouter exec/lancement de code-server ici — entrypoint.sh s'en charge.

MARKER="$HOME/.gamad-setup-done"

[ -f "$MARKER" ] && exit 0

echo "[gamad] Premier lancement — configuration du workspace..."

# ── Extension Claude Code (open-vsx via code-server) ───────────────────────
code-server --install-extension Anthropic.claude-code --force 2>/dev/null \
    && echo "[gamad] Extension Claude Code installée." \
    || echo "[gamad] Échec installation extension Claude Code."

# ── Node.js + Claude Code CLI ───────────────────────────────────────────────
if ! command -v claude &>/dev/null; then
    echo "[gamad] Installation de Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - -qq 2>/dev/null
    sudo apt-get install -y nodejs -qq 2>/dev/null \
        && npm install -g @anthropic-ai/claude-code --quiet 2>/dev/null \
        && echo "[gamad] Claude Code CLI installé." \
        || echo "[gamad] Échec installation Claude Code CLI."
fi

# ── Git global + GitHub token ───────────────────────────────────────────────
if [ -n "${GITHUB_TOKEN:-}" ]; then
    git config --global credential.helper store
    printf 'https://oauth2:%s@github.com\n' "${GITHUB_TOKEN}" > ~/.git-credentials
    chmod 600 ~/.git-credentials
    git config --global user.email "${GIT_USER_EMAIL:-user@gamad.net}"
    git config --global user.name  "${GIT_USER_NAME:-GamadCode User}"
    echo "[gamad] GitHub configuré."
fi

touch "$MARKER"
echo "[gamad] Setup terminé."
