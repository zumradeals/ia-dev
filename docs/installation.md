# Guide d'installation DevLab

## Prérequis

- Ubuntu Server 24.04 LTS (VPS, bare metal, VM)
- Accès root ou sudo
- Connexion Internet
- 10GB d'espace disque minimum
- 1GB RAM minimum (2GB recommandé)

## Étape 1 — Cloner le dépôt

```bash
# Cloner où vous voulez — DEVLAB_ROOT est auto-détecté
git clone https://github.com/zumradeals/ia-dev.git /devlab-bootstrap
cd /devlab-bootstrap
```

## Étape 2 — Configurer (optionnel, avant bootstrap)

```bash
# Configuration locale (gitignored)
cp config/default.env config/local.env

# Éditer les paramètres : utilisateur, ports, modules
nano config/local.env

# Activer/désactiver les modules
nano config/modules.conf

# Créer le fichier secrets (API keys, mots de passe)
cat > config/secrets.env << 'EOF'
ANTHROPIC_API_KEY=votre_clé_ici
OPENAI_API_KEY=votre_clé_ici
EOF
chmod 600 config/secrets.env
```

## Étape 3 — Bootstrap système

```bash
# setup.sh est le point d'entrée unique pour le premier lancement :
# - Détecte DEVLAB_ROOT automatiquement
# - Crée /usr/local/bin/devlab (symlink)
# - Lance le bootstrap complet
sudo bash setup.sh
```

Après `setup.sh`, la commande `devlab` est disponible partout.

Optionnel — vérifications seules avant bootstrap :
```bash
sudo bash bootstrap/00-preflight.sh
```

## Étape 4 — Installer les modules

```bash
# Tout installer (modules activés dans modules.conf)
devlab install all

# Ou module par module
devlab install languages/nodejs
devlab install languages/python
devlab install containers/docker
devlab install databases/postgresql
devlab install databases/redis
devlab install web/nginx
devlab install ai/claude-code
devlab install devtools/zsh
devlab install devtools/tmux
```

## Étape 5 — Vérifier

```bash
devlab status    # Registre des modules
devlab check     # Versions installées
devlab health    # Diagnostic complet
```

## Options globales

```bash
# Simulation sans exécution réelle
devlab install all --dry-run

# Accepter toutes les confirmations
devlab install all --yes

# Mode débogage
devlab install all --debug
```

## Réinstallation sur un autre VPS

```bash
# Sur le nouveau VPS
git clone <votre-repo> /opt/devlab-bootstrap
cd /opt/devlab-bootstrap

# Copier config/local.env et config/secrets.env depuis l'ancien
sudo devlab bootstrap
devlab install all
```

## Troubleshooting

### Un module échoue

```bash
# Voir les logs d'erreur
ls -lt logs/errors/
cat logs/errors/YYYYMMDD_HHMMSS_module.error.log

# Retirer du registre et réessayer
devlab reset <module>
devlab install <module> --debug
```

### L'état est désynchronisé

```bash
# Réconcilier registre et réalité système
devlab sync
```
