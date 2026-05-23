#!/usr/bin/env bash
# installers/devtools/20-tmux.sh — tmux + configuration DevLab

set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="devtools/tmux"

# shellcheck source=../../lib/core.sh
source "${DEVLAB_ROOT}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
source "${DEVLAB_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/state.sh
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "tmux" "install"
log_section "tmux"

DEVLAB_USER="${DEVLAB_USER:-devuser}"
USER_HOME=$(getent passwd "$DEVLAB_USER" | cut -d: -f6)

_do_install() {
    apt_install tmux

    local tmux_conf="${USER_HOME}/.tmux.conf"
    local template="${DEVLAB_ROOT}/configs/tmux/.tmux.conf.tpl"

    if [[ ! -f "$tmux_conf" ]]; then
        if [[ -f "$template" ]]; then
            render_template "$template" "$tmux_conf"
        else
            cat > "$tmux_conf" << 'EOF'
# DevLab tmux configuration
set -g default-terminal "screen-256color"
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g history-limit 50000
set -g status-bg colour235
set -g status-fg colour136
set -g status-left " #S "
set -g status-right " %H:%M %d-%m "
bind r source-file ~/.tmux.conf \; display "Config rechargée"
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
EOF
        fi
        chown "${DEVLAB_USER}:$(id -gn "$DEVLAB_USER")" "$tmux_conf"
        log_step "~/.tmux.conf configuré"
    else
        log_skip "~/.tmux.conf existe déjà"
    fi
}

installer_run \
    "devtools/tmux" \
    "tmux" \
    "tmux -V 2>/dev/null | awk '{print \$2}'" \
    "_do_install"
