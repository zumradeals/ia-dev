# DevLab tmux configuration
set -g default-terminal "screen-256color"
set -ga terminal-overrides ",xterm-256color:Tc"

# Souris activée
set -g mouse on

# Index à partir de 1 (plus ergonomique)
set -g base-index 1
setw -g pane-base-index 1

# Historique étendu
set -g history-limit 50000

# Délai ESC réduit
set -sg escape-time 10

# Reload config : <prefix> + r
bind r source-file ~/.tmux.conf \; display "Config rechargée"

# Splits intuitifs
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
unbind '"'
unbind %

# Navigation panes : Alt + flèches
bind -n M-Left select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up select-pane -U
bind -n M-Down select-pane -D

# Status bar
set -g status-bg colour235
set -g status-fg colour136
set -g status-left-length 30
set -g status-right-length 60
set -g status-left " #[bold]#S #[nobold]│ "
set -g status-right " #[dim]%d-%m-%Y #[nodim]%H:%M "
setw -g window-status-format " #I:#W "
setw -g window-status-current-format " #[bold]#I:#W #[nobold]"
setw -g window-status-current-style bg=colour24,fg=colour255

# Copie en mode vi
setw -g mode-keys vi
bind-key -T copy-mode-vi v send-keys -X begin-selection
bind-key -T copy-mode-vi y send-keys -X copy-selection
