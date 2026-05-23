# ~/.zsh_aliases — DevLab Aliases
# Généré par DevLab Bootstrap

# ── Navigation ────────────────────────────────
alias ..='cd ..'
alias ...='cd ../..'
alias workspace='cd ${DEVLAB_ROOT}/workspace/projects'
alias repos='cd ${DEVLAB_ROOT}/repositories'

# ── DevLab ────────────────────────────────────
alias dl='devlab'
alias dls='devlab status'
alias dlh='devlab health'
alias dli='devlab install'

# ── Git ───────────────────────────────────────
alias gs='git status'
alias gp='git push'
alias gl='git log --oneline --graph --decorate -20'
alias gd='git diff'
alias gc='git commit'
alias gco='git checkout'
alias gb='git branch'

# ── Docker ────────────────────────────────────
alias dc='docker compose'
alias dps='docker ps'
alias di='docker images'
alias dex='docker exec -it'

# ── Système ───────────────────────────────────
alias ports='ss -tlnp'
alias services='systemctl list-units --type=service --state=running'
alias mem='free -h'
alias cpu='htop'

# ── Logs DevLab ───────────────────────────────
alias devlogs='ls -lt ${DEVLAB_ROOT}/logs/install/ | head -10'
alias deberrors='ls -lt ${DEVLAB_ROOT}/logs/errors/ | head -10'
