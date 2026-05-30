#!/usr/bin/env bash
# Exécuté via ENTRYPOINTD avant le démarrage de code-server.
# Ne pas ajouter exec/lancement de code-server ici — entrypoint.sh s'en charge.

EXTENSIONS_CONF="/opt/gamadcode/extensions.conf"
EXTENSIONS_HASH=$(md5sum "$EXTENSIONS_CONF" 2>/dev/null | cut -d' ' -f1 || echo "none")
MARKER="$HOME/.gamad-setup-$EXTENSIONS_HASH"

# Si déjà configuré avec cette liste d'extensions → exit
[ -f "$MARKER" ] && exit 0

# Nettoyer les anciens marqueurs
rm -f "$HOME/.gamad-setup-"* 2>/dev/null

echo "[gamad] Configuration du workspace..."

# ── Extensions VS Code ───────────────────────────────────────────────────────
if [ -f "$EXTENSIONS_CONF" ]; then
    echo "[gamad] Installation des extensions..."
    while IFS= read -r ext || [ -n "$ext" ]; do
        [[ "$ext" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${ext// }" ]] && continue
        code-server --install-extension "$ext" --force 2>/dev/null \
            && echo "[gamad] ✓ $ext" \
            || echo "[gamad] ✗ $ext"
    done < "$EXTENSIONS_CONF"
fi

# ── Node.js + Claude Code CLI ────────────────────────────────────────────────
if ! command -v npm &>/dev/null; then
    echo "[gamad] Installation de Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1
    sudo apt-get install -y nodejs >/dev/null 2>&1
fi

if command -v npm &>/dev/null && [ ! -f "$HOME/.npm-global/bin/claude" ]; then
    echo "[gamad] Installation de Claude Code CLI..."
    mkdir -p "$HOME/.npm-global"
    npm config set prefix "$HOME/.npm-global"
    export PATH="$HOME/.npm-global/bin:$PATH"
    npm install -g @anthropic-ai/claude-code --quiet 2>/dev/null \
        && echo "[gamad] ✓ Claude Code CLI" \
        || echo "[gamad] ✗ Claude Code CLI"
    grep -qxF 'export PATH="$HOME/.npm-global/bin:$PATH"' ~/.bashrc 2>/dev/null \
        || echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc
fi

# Symlink claude dans le PATH système pour que l'extension VS Code le trouve
if [ -f "$HOME/.npm-global/bin/claude" ] && [ ! -f "/usr/local/bin/claude" ]; then
    sudo ln -sf "$HOME/.npm-global/bin/claude" /usr/local/bin/claude 2>/dev/null \
        && echo "[gamad] ✓ claude lié dans /usr/local/bin" \
        || echo "[gamad] ✗ symlink claude échoué"
fi

# Patch extension Claude Code : forcer Activity Bar (primary) au lieu de Secondary Sidebar
# La Secondary Sidebar ne fonctionne pas dans code-server derrière un reverse proxy
CLAUDE_EXT=$(find "$HOME/.local/share/code-server/extensions" -name "extension.js" -path "*/anthropic.claude-code*" 2>/dev/null | head -1)
if [ -n "$CLAUDE_EXT" ]; then
    sed -i 's/claudeVSCodeSidebarSecondary\.focus/claudeVSCodeSidebar.focus/g' "$CLAUDE_EXT" 2>/dev/null
    sed -i 's/getPreferredLocation()==="sidebar"&&G)/getPreferredLocation()==="sidebar")/g' "$CLAUDE_EXT" 2>/dev/null
    echo "[gamad] ✓ patch Claude Code (sidebar primaire)"
fi

# ── Settings VS Code (clés API + PATH npm) ──────────────────────────────────
python3 - <<'PYEOF' 2>/dev/null && echo "[gamad] ✓ Settings VS Code"
import json, os

d = os.path.expanduser("~/.local/share/code-server/User")
os.makedirs(d, exist_ok=True)
f = os.path.join(d, "settings.json")

existing = {}
try:
    with open(f) as fp: existing = json.load(fp)
except: pass

settings = {
    "telemetry.telemetryLevel": "off",
    "extensions.autoUpdate": False,
    "editor.fontSize": 14,
    "editor.tabSize": 2,
    "editor.formatOnSave": True,
    "git.autofetch": True,
    "terminal.integrated.defaultProfile.linux": "bash",
    "workbench.iconTheme": "material-icon-theme"
}

env = {k: os.environ[k] for k in ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GITHUB_TOKEN"] if os.environ.get(k)}
env["PATH"] = os.environ.get("HOME", "/home/coder") + "/.npm-global/bin:" + os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin")
settings["terminal.integrated.env.linux"] = env

existing.update(settings)
with open(f, "w") as fp: json.dump(existing, fp, indent=2)
PYEOF

# ── Git global + GitHub token ─────────────────────────────────────────────────
if [ -n "${GITHUB_TOKEN:-}" ]; then
    git config --global credential.helper store
    printf 'https://oauth2:%s@github.com\n' "${GITHUB_TOKEN}" > ~/.git-credentials
    chmod 600 ~/.git-credentials
    git config --global user.email "${GIT_USER_EMAIL:-user@gamad.net}"
    git config --global user.name  "${GIT_USER_NAME:-GamadCode User}"
    echo "[gamad] ✓ GitHub configuré"
fi

# Config Continue (Claude + OpenAI) générée à partir des clés injectées
if command -v python3 &>/dev/null; then
    python3 - <<'PYEOF' 2>/dev/null && echo "[gamad] ✓ Config Continue"
import json, os

cfg_dir = os.path.expanduser("~/.continue")
os.makedirs(cfg_dir, exist_ok=True)

models, autocomplete = [], None

ak = os.environ.get("ANTHROPIC_API_KEY", "")
if ak:
    models += [
        {"title": "Claude Sonnet", "provider": "anthropic", "model": "claude-sonnet-4-5", "apiKey": ak},
        {"title": "Claude Haiku",  "provider": "anthropic", "model": "claude-haiku-4-5-20251001", "apiKey": ak}
    ]
    autocomplete = {"title": "Claude Haiku (autocomplete)", "provider": "anthropic",
                    "model": "claude-haiku-4-5-20251001", "apiKey": ak}

ok = os.environ.get("OPENAI_API_KEY", "")
if ok:
    models += [{"title": "GPT-4o", "provider": "openai", "model": "gpt-4o", "apiKey": ok}]
    if not autocomplete:
        autocomplete = {"title": "GPT-4o-mini (autocomplete)", "provider": "openai",
                        "model": "gpt-4o-mini", "apiKey": ok}

if not models:
    exit(0)

cfg = {"models": models, "allowAnonymousTelemetry": False}
if autocomplete:
    cfg["tabAutocompleteModel"] = autocomplete

with open(os.path.join(cfg_dir, "config.json"), "w") as f:
    json.dump(cfg, f, indent=2)
PYEOF
fi

touch "$MARKER"
echo "[gamad] Setup terminé."
