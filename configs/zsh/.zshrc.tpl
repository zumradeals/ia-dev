# ~/.zshrc — DevLab Zsh configuration
# Généré par DevLab Bootstrap — personnalisez après installation

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"

plugins=(
    git
    docker
    docker-compose
    node
    npm
    python
    zsh-autosuggestions
    zsh-syntax-highlighting
    fzf
)

source $ZSH/oh-my-zsh.sh

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Go
export GOROOT=/usr/local/go
export GOPATH="$HOME/go"
export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"

# Rust
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

# DevLab
export DEVLAB_ROOT="${DEVLAB_ROOT}"
export PATH="${DEVLAB_ROOT}/bin:$PATH"

# Aliases DevLab
[ -f ~/.shell_aliases ] && source ~/.shell_aliases
[ -f ~/.zsh_aliases ] && source ~/.zsh_aliases

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Historique étendu
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
