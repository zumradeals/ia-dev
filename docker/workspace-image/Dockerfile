FROM gitpod/openvscode-server:latest

# ─────────────────────────────────────────────────────────────────────────────
# GamadCode Workspace Image
# Base : gitpod/openvscode-server
# Publie sous : zumradeals/gamadcode-workspace:latest
# ─────────────────────────────────────────────────────────────────────────────

USER root

# ── Dépendances système ───────────────────────────────────────────────────────
RUN apt-get update -q && \
    apt-get install -y --no-install-recommends \
        jq \
        sudo \
        curl \
        git \
        ca-certificates \
        gnupg \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Sudo passwordless pour l'utilisateur workspace ───────────────────────────
# Le startup script utilise sudo pour chown, apt-get install, etc.
RUN echo "openvscode-server ALL=(ALL) NOPASSWD:ALL" \
        > /etc/sudoers.d/gamadcode \
    && chmod 0440 /etc/sudoers.d/gamadcode

# ── GamadCode branding — patch product.json ──────────────────────────────────
# Remplace "OpenVSCode Server" dans : barre de titre, Help > About,
# splash screen, fenêtre de dialogue et toute référence interne à nameShort/nameLong.
# On utilise jq pour une substitution JSON propre (pas de sed fragile).
RUN PRODUCT_JSON="${OPENVSCODE_SERVER_ROOT}/product.json" \
    && jq ' \
        .nameShort           = "GamadCode Studio" \
        | .nameLong          = "GamadCode Studio" \
        | .win32DirName      = "GamadCode Studio" \
        | .win32NameVersion  = "GamadCode Studio" \
        | .win32AppUserModelId = "GamadCode.Studio" \
    ' "$PRODUCT_JSON" > /tmp/product.json \
    && mv /tmp/product.json "$PRODUCT_JSON" \
    && echo "[gamad] product.json → $(jq -r .nameShort "$PRODUCT_JSON")"

# ── Node.js LTS pré-installé ─────────────────────────────────────────────────
# Évite le téléchargement (60s+) à chaque premier démarrage de workspace.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && echo "[gamad] Node.js $(node --version)"

# ── Claude Code CLI pré-installé ─────────────────────────────────────────────
# Installé globalement : disponible immédiatement dans tout nouveau workspace.
RUN npm install -g @anthropic-ai/claude-code --quiet 2>/dev/null \
    && ln -sf "$(npm root -g)/../bin/claude" /usr/local/bin/claude \
    && echo "[gamad] Claude Code CLI $(claude --version 2>/dev/null | head -1 || echo 'installed')"

# ── Retour à l'utilisateur non-root ──────────────────────────────────────────
USER openvscode-server
WORKDIR /home/workspace
