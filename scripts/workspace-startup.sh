#!/bin/sh
# Script de démarrage GamadCode — OpenVSCode Server
# On est le ENTRYPOINT : faire le setup puis lancer le serveur.

EXTENSIONS_CONF="/opt/gamadcode/extensions.conf"
EXT_HASH=$(md5sum "$EXTENSIONS_CONF" 2>/dev/null | cut -d' ' -f1 || echo "none")
SERVER_VER=$("$OPENVSCODE_SERVER_ROOT/bin/openvscode-server" --version 2>/dev/null | head -1 | tr ' ' '-')
CLAUDE_VER=$(find "$HOME/.openvscode-server/extensions" \
    -name "package.json" -path "*/anthropic.claude*" \
    -exec node -e "try{process.stdout.write(require(process.argv[1]).version)}catch{}" {} \; \
    2>/dev/null | head -1 || echo "0")
MARKER="$HOME/.gamad-setup-${EXT_HASH:0:8}-${SERVER_VER}-c${CLAUDE_VER//./}"

if [ ! -f "$MARKER" ]; then
    # Corriger les permissions du volume (peut être root si clonage fait en root)
    sudo chown -R "$(id -u):$(id -g)" "$HOME" 2>/dev/null || true

    # Nettoyer les anciens marqueurs
    rm -f "$HOME/.gamad-setup-"* 2>/dev/null
    echo "[gamad] Configuration du workspace (${SERVER_VER})..."

    # ── Extensions ─────────────────────────────────────────────────────────
    if [ -f "$EXTENSIONS_CONF" ]; then
        echo "[gamad] Installation des extensions..."
        while IFS= read -r ext || [ -n "$ext" ]; do
            case "$ext" in '#'*|'') continue ;; esac
            "$OPENVSCODE_SERVER_ROOT/bin/openvscode-server" --install-extension "$ext" --force 2>/dev/null \
                && echo "[gamad] ✓ $ext" || echo "[gamad] ✗ $ext"
        done < "$EXTENSIONS_CONF"
    fi

    # ── Node.js + Claude Code CLI ──────────────────────────────────────────
    if ! command -v npm >/dev/null 2>&1; then
        echo "[gamad] Installation de Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1
        sudo apt-get install -y nodejs >/dev/null 2>&1
    fi

    if command -v npm >/dev/null 2>&1 && [ ! -f "$HOME/.npm-global/bin/claude" ]; then
        echo "[gamad] Installation de Claude Code CLI..."
        mkdir -p "$HOME/.npm-global"
        npm config set prefix "$HOME/.npm-global"
        export PATH="$HOME/.npm-global/bin:$PATH"
        npm install -g @anthropic-ai/claude-code --quiet 2>/dev/null \
            && echo "[gamad] ✓ Claude Code CLI" || echo "[gamad] ✗ Claude Code CLI"
        grep -qxF 'export PATH="$HOME/.npm-global/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null \
            || echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"
    fi

    # Symlink claude dans PATH système → visible par l'extension VS Code
    if [ -f "$HOME/.npm-global/bin/claude" ] && [ ! -f "/usr/local/bin/claude" ]; then
        sudo ln -sf "$HOME/.npm-global/bin/claude" /usr/local/bin/claude 2>/dev/null \
            && echo "[gamad] ✓ claude dans /usr/local/bin"
    fi

    # ── Auth Claude Code : injecter la clé API dans la config extension ───
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        mkdir -p "$HOME/.claude"

        # Écrire settings.json pour l'extension VS Code
        node - <<'JSEOF' 2>/dev/null \
            && echo "[gamad] ✓ Claude Code auth configurée" \
            || echo "[gamad] ✗ Erreur config Claude Code auth (non bloquant)"
const fs   = require('fs');
const dir  = process.env.HOME + '/.claude';
const f    = dir + '/settings.json';
const key  = process.env.ANTHROPIC_API_KEY;
if (!key) process.exit(0);
let s = {};
try { s = JSON.parse(fs.readFileSync(f, 'utf8')); } catch {}
// Structure attendue par l'extension Claude Code
s.primaryApiKey = key;
if (!s.hasCompletedOnboarding) s.hasCompletedOnboarding = true;
if (!s.hasAcknowledgedCostThreshold) s.hasAcknowledgedCostThreshold = true;
fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(f, JSON.stringify(s, null, 2), { mode: 0o600 });
JSEOF

        # Écrire aussi .credentials (format alternatif selon version extension)
        node - <<'JSEOF' 2>/dev/null
const fs  = require('fs');
const dir = process.env.HOME + '/.claude';
const f   = dir + '/.credentials';
const key = process.env.ANTHROPIC_API_KEY;
if (!key) process.exit(0);
fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(f, JSON.stringify({ claudeAiOauthTokenData: null, primaryApiKey: key }, null, 2), { mode: 0o600 });
JSEOF

        # Configurer aussi via claude CLI (si disponible)
        export PATH="$HOME/.npm-global/bin:/usr/local/bin:$PATH"
        if command -v claude >/dev/null 2>&1; then
            claude config set primaryApiKey "$ANTHROPIC_API_KEY" 2>/dev/null \
                && echo "[gamad] ✓ Claude CLI configuré" \
                || true
        fi
    else
        echo "[gamad] ℹ ANTHROPIC_API_KEY absent — connexion manuelle requise"
    fi

    # ── Claude Code : configuration via settings officiels ────────────────
    # Remplace le patch sed fragile sur le JS minifié de l'extension.
    # Approche : settings.json + keybindings.json injectés avant le lancement.
    echo "[gamad] Configuration Claude Code (sidebar primaire)..."

    node - <<'JSEOF' 2>/dev/null \
        && echo "[gamad] ✓ Claude Code configuré" \
        || echo "[gamad] ✗ Erreur config Claude Code (non bloquant)"
const fs = require('fs');
const dir = process.env.HOME + '/.openvscode-server/data/User';
fs.mkdirSync(dir, { recursive: true });
const f = dir + '/settings.json';
let s = {};
try { s = JSON.parse(fs.readFileSync(f, 'utf8')); } catch {}
Object.assign(s, {
  'workbench.secondarySideBar.defaultVisibility': 'hidden',
  'claude.preferredPanel': 'sidebar',
  'workbench.startupEditor': 'none',
  'workbench.sideBar.location': 'left',
  'workbench.activityBar.visible': true
});
fs.writeFileSync(f, JSON.stringify(s, null, 2));
JSEOF

    node - <<'JSEOF' 2>/dev/null \
        && echo "[gamad] ✓ Keybinding Ctrl+Shift+A → Claude Code"
const fs = require('fs');
const dir = process.env.HOME + '/.openvscode-server/data/User';
const f = dir + '/keybindings.json';
let kb = [];
try { kb = JSON.parse(fs.readFileSync(f, 'utf8')); } catch {}
kb = kb.filter(k => !String(k.command || '').includes('claude'));
kb.push({ "key": "ctrl+shift+a", "command": "claudeVSCodeSidebar.focus" });
fs.writeFileSync(f, JSON.stringify(kb, null, 2));
JSEOF

    # ── Settings VS Code ────────────────────────────────────────────────────
    SETTINGS_DIR="$HOME/.openvscode-server/data/User"
    mkdir -p "$SETTINGS_DIR"

    if command -v node >/dev/null 2>&1; then
        node - <<JSEOF 2>/dev/null && echo "[gamad] ✓ Settings VS Code"
const fs = require('fs'), os = require('os');
const dir = os.homedir() + '/.openvscode-server/data/User';
fs.mkdirSync(dir, {recursive:true});
const f = dir + '/settings.json';
let existing = {};
try { existing = JSON.parse(fs.readFileSync(f,'utf8')); } catch{}
const env = {};
for (const k of ['ANTHROPIC_API_KEY','OPENAI_API_KEY','GITHUB_TOKEN']) {
    if (process.env[k]) env[k] = process.env[k];
}
env.PATH = (process.env.HOME||'/home/workspace') + '/.npm-global/bin:' + (process.env.PATH||'/usr/local/bin:/usr/bin:/bin');
Object.assign(existing, {
    'telemetry.telemetryLevel': 'off',
    'extensions.autoUpdate': false,
    'editor.fontSize': 14, 'editor.tabSize': 2, 'editor.formatOnSave': true,
    'git.autofetch': true,
    'remote.autoForwardPorts': true,
    'remote.autoForwardPortsSource': 'process',
    'terminal.integrated.defaultProfile.linux': 'bash',
    'terminal.integrated.env.linux': env,
    'workbench.iconTheme': 'material-icon-theme',
    'files.exclude': {
        '**/.gamad-setup-*': true,
        '**/.openvscode-server': true,
        '**/.npm-global': true,
        '**/.npm': true,
        '**/.cache': true,
        '**/.continue': true,
        '**/.git-credentials': true
    }
});
fs.writeFileSync(f, JSON.stringify(existing, null, 2));
JSEOF
    fi

    # ── Config Continue (Claude + OpenAI) ──────────────────────────────────
    if command -v node >/dev/null 2>&1; then
        node - <<JSEOF 2>/dev/null && echo "[gamad] ✓ Config Continue"
const fs = require('fs'), os = require('os');
const dir = os.homedir() + '/.continue';
fs.mkdirSync(dir, {recursive:true});
const ak = process.env.ANTHROPIC_API_KEY||'', ok = process.env.OPENAI_API_KEY||'';
const models = [];
if (ak) {
    models.push({title:'Claude Sonnet',provider:'anthropic',model:'claude-sonnet-4-5',apiKey:ak});
    models.push({title:'Claude Haiku', provider:'anthropic',model:'claude-haiku-4-5-20251001',apiKey:ak});
}
if (ok) models.push({title:'GPT-4o',provider:'openai',model:'gpt-4o',apiKey:ok});
if (!models.length) process.exit(0);
const cfg = {models, allowAnonymousTelemetry:false};
if (ak) cfg.tabAutocompleteModel = {title:'Haiku',provider:'anthropic',model:'claude-haiku-4-5-20251001',apiKey:ak};
fs.writeFileSync(dir+'/config.json', JSON.stringify(cfg,null,2));
JSEOF
    fi

    # ── Git + GitHub token ──────────────────────────────────────────────────
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        git config --global credential.helper store
        printf 'https://oauth2:%s@github.com\n' "${GITHUB_TOKEN}" > "$HOME/.git-credentials"
        chmod 600 "$HOME/.git-credentials"
        git config --global user.email "${GIT_USER_EMAIL:-user@gamad.net}"
        git config --global user.name  "${GIT_USER_NAME:-GamadCode User}"
        echo "[gamad] ✓ GitHub configuré"
    fi

    touch "$MARKER"
    echo "[gamad] Setup terminé."
fi

# ── Lancement du serveur ────────────────────────────────────────────────────
exec "$OPENVSCODE_SERVER_ROOT/bin/openvscode-server" \
    --host 0.0.0.0 \
    --port 8080 \
    --without-connection-token \
    /home/workspace
