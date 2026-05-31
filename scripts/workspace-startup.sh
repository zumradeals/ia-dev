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
LAUNCHER_VER="1.0.3"
MARKER="$HOME/.gamad-setup-${EXT_HASH:0:8}-${SERVER_VER}-c${CLAUDE_VER//./}-l${LAUNCHER_VER}"

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

    # ── Extension compagnon : GamadCode Launcher ──────────────────────────────
    # Boutons barre d'état (Claude / Codex) + auto-lancement via marqueur .gamad/autostart
    LAUNCHER_DIR="$HOME/.openvscode-server/extensions/gamadcode-launcher"
    mkdir -p "$LAUNCHER_DIR"

    cat > "$LAUNCHER_DIR/package.json" << 'PKGEOF'
{
  "name": "gamadcode-launcher",
  "displayName": "GamadCode Launcher",
  "description": "Boutons Claude/Codex + page de bienvenue GamadCode Studio",
  "version": "1.0.3",
  "publisher": "gamadcode",
  "engines": { "vscode": "^1.80.0" },
  "main": "./extension.js",
  "activationEvents": ["onStartupFinished"],
  "contributes": {
    "commands": [
      { "command": "gamadcode.openClaude",     "title": "GamadCode : Ouvrir Claude" },
      { "command": "gamadcode.openCodex",      "title": "GamadCode : Ouvrir Codex" },
      { "command": "gamadcode.openWelcome",    "title": "GamadCode : Ouvrir la page d'accueil" },
      { "command": "gamadcode.claudeInTerminal","title": "GamadCode : Ouvrir Claude dans le terminal" }
    ]
  }
}
PKGEOF

    cat > "$LAUNCHER_DIR/extension.js" << 'JSEOF'
const vscode = require('vscode');
const fs     = require('fs');
const path   = require('path');

let fallbackShown = false;

// ── Helpers ──────────────────────────────────────────────────────────────────
function openInTerminal(name, cmd) {
  const term = vscode.window.createTerminal(name);
  term.show();
  term.sendText(cmd);
}

function offerTerminalFallback() {
  if (fallbackShown) return;
  fallbackShown = true;
  vscode.window.showInformationMessage(
    'Claude est ouvert. Si le panneau reste vide, ouvrez-le dans le terminal.',
    'Ouvrir dans le terminal'
  ).then(c => { if (c) openInTerminal('Claude', 'claude'); });
}

async function openClaude() {
  try {
    const cmds = await vscode.commands.getCommands(true);
    if (cmds.includes('claudeVSCodeSidebar.focus')) {
      await vscode.commands.executeCommand('claudeVSCodeSidebar.focus');
      offerTerminalFallback();
      return;
    }
  } catch (e) {}
  openInTerminal('Claude', 'claude');
}

// ── Welcome panel ─────────────────────────────────────────────────────────────
function openWelcomePanel(context) {
  const panel = vscode.window.createWebviewPanel(
    'gamadcodeWelcome',
    'GamadCode Studio',
    vscode.ViewColumn.One,
    { enableScripts: false, retainContextWhenHidden: false }
  );

  const hasAnthropic = fs.existsSync(path.join(process.env.HOME || '', '.claude', 'settings.json'));
  const claudeVer    = process.env.CLAUDE_VERSION || '';

  panel.webview.html = `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:#0a0a14;color:#e2e8f0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;min-height:100vh;display:flex;align-items:flex-start;justify-content:center;padding:48px 24px}
  .wrap{max-width:660px;width:100%}
  .hero{text-align:center;padding:0 0 48px}
  .logo{font-size:42px;font-weight:900;background:linear-gradient(135deg,#6366f1,#a855f7);-webkit-background-clip:text;-webkit-text-fill-color:transparent;letter-spacing:-1px}
  .tagline{color:#64748b;font-size:15px;margin-top:8px}
  .status{display:inline-flex;align-items:center;gap:6px;margin-top:16px;padding:4px 14px;border-radius:999px;font-size:12px;font-weight:600;background:rgba(34,197,94,.1);color:#22c55e;border:1px solid rgba(34,197,94,.3)}
  .dot{width:6px;height:6px;border-radius:50%;background:currentColor}
  h2{font-size:13px;font-weight:700;color:#64748b;text-transform:uppercase;letter-spacing:.8px;margin-bottom:14px}
  .grid{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:28px}
  .card{background:#12121f;border:1px solid #1e1e35;border-radius:14px;padding:20px;transition:border-color .2s}
  .card:hover{border-color:#6366f1}
  .card-icon{font-size:28px;margin-bottom:10px}
  .card-title{font-size:15px;font-weight:700;margin-bottom:4px}
  .card-desc{font-size:12px;color:#64748b;margin-bottom:14px;line-height:1.5}
  .kbd{display:inline-block;background:#1e1e35;border:1px solid #2d2d4e;border-radius:5px;padding:3px 8px;font-size:11px;font-family:monospace;color:#a5b4fc}
  .shortcuts{background:#12121f;border:1px solid #1e1e35;border-radius:14px;padding:20px;margin-bottom:28px}
  .shortcut-row{display:flex;justify-content:space-between;align-items:center;padding:8px 0;border-bottom:1px solid #1e1e35;font-size:13px}
  .shortcut-row:last-child{border-bottom:none}
  .shortcut-label{color:#94a3b8}
  .tip{background:rgba(99,102,241,.08);border:1px solid rgba(99,102,241,.2);border-radius:14px;padding:18px 20px;font-size:13px;color:#94a3b8;line-height:1.6}
  .tip strong{color:#a5b4fc}
</style>
</head>
<body>
<div class="wrap">

  <div class="hero">
    <div class="logo">GamadCode Studio</div>
    <div class="tagline">Votre environnement de développement IA</div>
    <div class="status"><span class="dot"></span> Workspace prêt</div>
  </div>

  <h2>Outils IA</h2>
  <div class="grid">
    <div class="card">
      <div class="card-icon">🤖</div>
      <div class="card-title">Claude Code</div>
      <div class="card-desc">Assistant IA d'Anthropic intégré directement dans votre éditeur.</div>
      <span class="kbd">Ctrl+Shift+A</span>
    </div>
    <div class="card">
      <div class="card-icon">✨</div>
      <div class="card-title">Codex CLI</div>
      <div class="card-desc">Génération de code OpenAI depuis le terminal intégré.</div>
      <span class="kbd">codex</span> dans le terminal
    </div>
  </div>

  <h2>Raccourcis</h2>
  <div class="shortcuts">
    <div class="shortcut-row"><span class="shortcut-label">Ouvrir Claude Code</span><span class="kbd">Ctrl+Shift+A</span></div>
    <div class="shortcut-row"><span class="shortcut-label">Terminal intégré</span><span class="kbd">Ctrl+&#96;</span></div>
    <div class="shortcut-row"><span class="shortcut-label">Palette de commandes</span><span class="kbd">Ctrl+Shift+P</span></div>
    <div class="shortcut-row"><span class="shortcut-label">Recherche de fichiers</span><span class="kbd">Ctrl+P</span></div>
    <div class="shortcut-row"><span class="shortcut-label">Recherche dans les fichiers</span><span class="kbd">Ctrl+Shift+F</span></div>
    <div class="shortcut-row"><span class="shortcut-label">Enregistrer</span><span class="kbd">Ctrl+S</span></div>
  </div>

  <div class="tip">
    <strong>Astuce :</strong> Cliquez sur les boutons <strong>$(sparkle) Claude</strong> et <strong>$(rocket) Codex</strong>
    dans la barre de statut (en bas) pour lancer vos outils IA directement.
    Votre clé Anthropic est ${hasAnthropic ? '<strong style="color:#22c55e">configurée</strong> et injectée automatiquement.' : '<strong style="color:#fbbf24">non détectée</strong> — connectez-vous sur app.gamad.net pour la configurer.'}
  </div>

</div>
</body>
</html>`;
}

// ── Activate ──────────────────────────────────────────────────────────────────
function activate(context) {
  // Boutons barre de statut
  const claudeBtn = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
  claudeBtn.text    = '$(sparkle) Claude';
  claudeBtn.tooltip = 'Ouvrir Claude Code';
  claudeBtn.command = 'gamadcode.openClaude';
  claudeBtn.show();

  const codexBtn = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 99);
  codexBtn.text    = '$(rocket) Codex';
  codexBtn.tooltip = 'Ouvrir OpenAI Codex';
  codexBtn.command = 'gamadcode.openCodex';
  codexBtn.show();

  context.subscriptions.push(
    claudeBtn, codexBtn,
    vscode.commands.registerCommand('gamadcode.openClaude',      () => openClaude()),
    vscode.commands.registerCommand('gamadcode.openCodex',       () => openInTerminal('Codex', 'codex')),
    vscode.commands.registerCommand('gamadcode.openWelcome',     () => openWelcomePanel(context)),
    vscode.commands.registerCommand('gamadcode.claudeInTerminal',() => openInTerminal('Claude', 'claude'))
  );

  // Page de bienvenue à la première ouverture du workspace
  if (!context.globalState.get('gamadcode.welcomeShown.v1')) {
    context.globalState.update('gamadcode.welcomeShown.v1', true);
    openWelcomePanel(context);
  }

  // Auto-lancement via marqueur .gamad/autostart
  const folder = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
  if (!folder) return;
  const marker = path.join(folder.uri.fsPath, '.gamad', 'autostart');

  const check = () => {
    let raw;
    try { raw = fs.readFileSync(marker, 'utf8').trim(); } catch (e) { return; }
    if (!raw) return;
    const parts = raw.split(':');
    const tool  = parts[0];
    const nonce = parts[1] || '';
    const ts    = parseInt(parts[2] || '0', 10);
    if (!nonce || Date.now() - ts > 300000) { try { fs.unlinkSync(marker); } catch {} return; }
    if (nonce === context.globalState.get('lastNonce')) return;
    context.globalState.update('lastNonce', nonce);
    if (tool === 'claude') openClaude();
    else if (tool === 'codex') openInTerminal('Codex', 'codex');
    try { fs.unlinkSync(marker); } catch (e) {}
  };

  check();
  fs.watchFile(marker, { interval: 1500 }, check);
  context.subscriptions.push({ dispose: () => fs.unwatchFile(marker) });
}

function deactivate() {}
module.exports = { activate, deactivate };
JSEOF

    echo "[gamad] ✓ Extension GamadCode Launcher"

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
    // ── Telemetry & updates ────────────────────────────────────────────────
    'telemetry.telemetryLevel': 'off',
    'extensions.autoUpdate': false,
    'update.mode': 'none',
    'workbench.tips.enabled': false,

    // ── GamadCode branding ─────────────────────────────────────────────────
    // Remplace "OpenVSCode Server" dans la barre de titre
    'window.title': 'GamadCode Studio — ${activeEditorShort}${separator}${rootName}',
    'workbench.colorTheme': 'Default Dark Modern',
    'workbench.startupEditor': 'none',
    'workbench.colorCustomizations': {
        // Barre de titre
        'titleBar.activeBackground': '#0d0d1a',
        'titleBar.activeForeground': '#e2e8f0',
        'titleBar.inactiveBackground': '#0d0d1a',
        'titleBar.inactiveForeground': '#64748b',
        'titleBar.border': '#1e1e35',
        // Barre d'activité (icônes gauche)
        'activityBar.background': '#0d0d1a',
        'activityBar.foreground': '#a5b4fc',
        'activityBar.inactiveForeground': '#475569',
        'activityBar.activeBorder': '#6366f1',
        'activityBar.border': '#1e1e35',
        // Panneau latéral
        'sideBar.background': '#12121f',
        'sideBar.foreground': '#cbd5e1',
        'sideBar.border': '#1e1e35',
        'sideBarSectionHeader.background': '#0d0d1a',
        'sideBarSectionHeader.foreground': '#94a3b8',
        'sideBarSectionHeader.border': '#1e1e35',
        // Éditeur
        'editor.background': '#0a0a14',
        'editorGroupHeader.tabsBackground': '#0d0d1a',
        'editorGroupHeader.tabsBorder': '#1e1e35',
        'tab.activeBackground': '#12121f',
        'tab.inactiveBackground': '#0d0d1a',
        'tab.border': '#1e1e35',
        'tab.activeBorderTop': '#6366f1',
        // Barre de statut — signature GamadCode violette
        'statusBar.background': '#6366f1',
        'statusBar.foreground': '#ffffff',
        'statusBar.noFolderBackground': '#4f46e5',
        'statusBar.debuggingBackground': '#a855f7',
        'statusBar.border': 'transparent',
        // Panneau (terminal)
        'panel.background': '#0d0d1a',
        'panel.border': '#1e1e35',
        'panelTitle.activeBorder': '#6366f1',
        // Input / dropdown
        'input.background': '#12121f',
        'input.border': '#1e1e35',
        'input.foreground': '#e2e8f0',
        'focusBorder': '#6366f1'
    },

    // ── Éditeur ────────────────────────────────────────────────────────────
    'editor.fontSize': 14,
    'editor.tabSize': 2,
    'editor.formatOnSave': true,
    'editor.minimap.enabled': false,
    'editor.renderWhitespace': 'none',
    'editor.cursorBlinking': 'smooth',
    'editor.fontLigatures': true,

    // ── Git & outils ───────────────────────────────────────────────────────
    'git.autofetch': true,
    'remote.autoForwardPorts': true,
    'remote.autoForwardPortsSource': 'process',
    'terminal.integrated.defaultProfile.linux': 'bash',
    'terminal.integrated.env.linux': env,
    'workbench.iconTheme': 'material-icon-theme',

    // ── Fichiers cachés (infra) ────────────────────────────────────────────
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
