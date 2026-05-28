#!/usr/bin/env bash
# installers/devtools/60-git-github.sh — GitHub CLI + clé SSH + config git globale
# GitHub comme source de vérité : gh CLI, auth SSH, git config, helper clone

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="devtools/git-github"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"
# shellcheck source=../../lib/checks.sh
source "${DEVLAB_ROOT}/lib/checks.sh"

log_init "git-github" "install"
log_section "GitHub CLI + SSH + Git config"

DEVLAB_USER="${DEVLAB_USER:-devuser}"
USER_HOME=$(getent passwd "$DEVLAB_USER" | cut -d: -f6)
SSH_KEY="${USER_HOME}/.ssh/id_ed25519"
SSH_CONFIG="${USER_HOME}/.ssh/config"
GIT_USER_NAME="${GIT_USER_NAME:-}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-}"
GIT_DEFAULT_BRANCH="${GIT_DEFAULT_BRANCH:-main}"

# ─────────────────────────────────────────────
# 1. GitHub CLI (gh)
# ─────────────────────────────────────────────
_install_gh_cli() {
    local keyfile="/etc/apt/keyrings/githubcli-archive-keyring.gpg"
    local listfile="/etc/apt/sources.list.d/github-cli.list"

    if [[ ! -f "$keyfile" ]]; then
        log_step "Ajout clé GPG GitHub CLI..."
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            | gpg --dearmor -o "$keyfile"
        chmod go+r "$keyfile"
    fi

    if [[ ! -f "$listfile" ]]; then
        log_step "Ajout dépôt GitHub CLI..."
        echo "deb [arch=$(dpkg --print-architecture) signed-by=${keyfile}] https://cli.github.com/packages stable main" \
            > "$listfile"
        apt_update
    fi

    apt_install gh
    log_ok "GitHub CLI installé ($(gh --version 2>/dev/null | head -1 | awk '{print $3}'))"
}

# ─────────────────────────────────────────────
# 2. Config git globale
# ─────────────────────────────────────────────
_configure_git_globals() {
    log_step "Configuration git globale pour ${DEVLAB_USER}..."

    if [[ -n "$GIT_USER_NAME" ]]; then
        sudo -u "$DEVLAB_USER" git config --global user.name "$GIT_USER_NAME"
        log_step "git user.name = ${GIT_USER_NAME}"
    else
        log_warn "GIT_USER_NAME non défini — configurez-le dans config/local.env"
    fi

    if [[ -n "$GIT_USER_EMAIL" ]]; then
        sudo -u "$DEVLAB_USER" git config --global user.email "$GIT_USER_EMAIL"
        log_step "git user.email = ${GIT_USER_EMAIL}"
    else
        log_warn "GIT_USER_EMAIL non défini — configurez-le dans config/local.env"
    fi

    # Paramètres git recommandés
    sudo -u "$DEVLAB_USER" git config --global init.defaultBranch "$GIT_DEFAULT_BRANCH"
    sudo -u "$DEVLAB_USER" git config --global pull.rebase false
    sudo -u "$DEVLAB_USER" git config --global push.autoSetupRemote true
    sudo -u "$DEVLAB_USER" git config --global core.autocrlf input
    sudo -u "$DEVLAB_USER" git config --global core.editor "vim"
    sudo -u "$DEVLAB_USER" git config --global fetch.prune true

    # Activer delta comme pager diff si installé
    if command_exists delta; then
        sudo -u "$DEVLAB_USER" git config --global core.pager "delta"
        sudo -u "$DEVLAB_USER" git config --global interactive.diffFilter "delta --color-only"
        sudo -u "$DEVLAB_USER" git config --global delta.navigate true
        sudo -u "$DEVLAB_USER" git config --global delta.light false
    fi

    log_ok "Git global configuré (branche par défaut : ${GIT_DEFAULT_BRANCH})"
}

# ─────────────────────────────────────────────
# 3. Clé SSH pour GitHub
# ─────────────────────────────────────────────
_setup_ssh_key() {
    mkdir -p "${USER_HOME}/.ssh"
    chmod 700 "${USER_HOME}/.ssh"
    local user_group; user_group=$(id -gn "$DEVLAB_USER" 2>/dev/null || echo "$DEVLAB_USER")

    if [[ -f "$SSH_KEY" ]]; then
        log_skip "Clé SSH déjà présente : ${SSH_KEY}"
    else
        local email_comment="${GIT_USER_EMAIL:-devlab@$(hostname -f 2>/dev/null || hostname)}"
        log_step "Génération clé SSH ed25519..."
        sudo -u "$DEVLAB_USER" ssh-keygen \
            -t ed25519 \
            -C "$email_comment" \
            -f "$SSH_KEY" \
            -N ""
        chmod 600 "${SSH_KEY}"
        chmod 644 "${SSH_KEY}.pub"
        chown "${DEVLAB_USER}:${user_group}" "${SSH_KEY}" "${SSH_KEY}.pub"
        log_ok "Clé SSH générée : ${SSH_KEY}"
    fi

    # Config SSH pour github.com
    if ! grep -q "Host github.com" "$SSH_CONFIG" 2>/dev/null; then
        cat >> "$SSH_CONFIG" << EOF

Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ServerAliveInterval 60
EOF
        chmod 600 "$SSH_CONFIG"
        chown "${DEVLAB_USER}:${user_group}" "$SSH_CONFIG"
        log_step "~/.ssh/config configuré pour github.com"
    else
        log_skip "~/.ssh/config : entrée github.com déjà présente"
    fi
}

# ─────────────────────────────────────────────
# 4. Helper de clonage dans workspace
# ─────────────────────────────────────────────
_install_clone_helper() {
    local helper="/usr/local/bin/gclone"
    cat > "$helper" << 'HELPER'
#!/usr/bin/env bash
# gclone — Clone un repo GitHub dans le workspace DevLab
# Usage: gclone <user/repo> [dossier-destination]
set -euo pipefail

REPO="${1:-}"
[[ -z "$REPO" ]] && { echo "Usage: gclone <user/repo> [destination]"; exit 1; }

WORKSPACE="${DEVLAB_ROOT:-/devlab}/workspace/projects"
DEST="${2:-$(basename "$REPO" .git)}"
TARGET="${WORKSPACE}/${DEST}"

mkdir -p "$WORKSPACE"

if [[ -d "$TARGET/.git" ]]; then
    echo "[SKIP] Déjà cloné : ${TARGET}"
    cd "$TARGET" && git pull
else
    echo "[CLONE] git@github.com:${REPO}.git → ${TARGET}"
    git clone "git@github.com:${REPO}.git" "$TARGET"
fi

echo ""
echo "  Projet : ${TARGET}"
echo "  cd ${TARGET}"
HELPER
    chmod +x "$helper"
    log_ok "Helper 'gclone' installé → gclone user/repo"
}

# ─────────────────────────────────────────────
# INSTALLATION
# ─────────────────────────────────────────────
_do_install() {
    _install_gh_cli
    _configure_git_globals
    _setup_ssh_key
    _install_clone_helper
}

installer_run \
    "devtools/git-github" \
    "GitHub CLI + SSH + Git config" \
    "gh --version 2>/dev/null | head -1 | awk '{print \$3}'" \
    "_do_install"

# ─────────────────────────────────────────────
# AFFICHAGE CLÉ PUBLIQUE — action requise
# ─────────────────────────────────────────────
echo
log_section "Action requise : Ajouter la clé SSH à GitHub"
echo
printf "  Copiez cette clé publique dans GitHub → Settings → SSH Keys :\n\n"
printf "  %s\n\n" "$(cat "${SSH_KEY}.pub" 2>/dev/null || echo '(clé non trouvée)')"
printf "  Lien direct : https://github.com/settings/ssh/new\n\n"
printf "  Testez ensuite avec : sudo -u %s ssh -T git@github.com\n" "$DEVLAB_USER"
echo
log_info "Authentification gh CLI : sudo -u ${DEVLAB_USER} gh auth login"
