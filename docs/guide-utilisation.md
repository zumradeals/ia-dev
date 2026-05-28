# Guide d'utilisation — DevLab IA

## Table des matières

1. [Premier démarrage après installation](#1-premier-démarrage-après-installation)
2. [Activer Claude Code](#2-activer-claude-code)
3. [Utiliser Claude Code au quotidien](#3-utiliser-claude-code-au-quotidien)
4. [Configuration GitHub complète](#4-configuration-github-complète)
5. [Travailler avec des projets](#5-travailler-avec-des-projets)
6. [Commandes devlab essentielles](#6-commandes-devlab-essentielles)
7. [Les modules — utilisation quotidienne](#7-les-modules--utilisation-quotidienne)
8. [Configuration locale et secrets](#8-configuration-locale-et-secrets)
9. [Ajouter un nouveau module](#9-ajouter-un-nouveau-module)

---

## 1. Premier démarrage après installation

Après le bootstrap et `devlab install all`, connectez-vous en tant que `devuser` pour travailler :

```bash
# Depuis root, basculer vers l'utilisateur de développement
su - devuser

# Vérifier que tout est en place
devlab status       # liste ce qui est installé
devlab health       # diagnostic complet
devlab check        # versions de tous les outils
```

> **Pourquoi devuser ?** C'est l'utilisateur dédié au développement. Les outils (Node.js via nvm, Claude Code, Python, etc.) sont installés dans son environnement, pas en global root.

---

## 2. Activer Claude Code

### Étape 1 — Obtenir une clé API Anthropic

1. Aller sur https://console.anthropic.com
2. Créer un compte ou se connecter
3. **API Keys** → **Create Key**
4. Copier la clé (commence par `sk-ant-...`)

### Étape 2 — Configurer la clé sur le VPS

La clé ne doit **jamais** être commitée dans Git. Elle se place dans `config/secrets.env` (gitignored) :

```bash
# En tant que root ou avec sudo depuis le dossier du projet
nano /devlab-bootstrap/config/secrets.env
```

Ajouter :

```bash
ANTHROPIC_API_KEY=sk-ant-VOTRE_CLE_ICI
```

Sécuriser le fichier :

```bash
chmod 600 /devlab-bootstrap/config/secrets.env
```

### Étape 3 — Vérifier que Claude Code est disponible

```bash
su - devuser
claude --version
```

Si la commande n'est pas trouvée, recharger l'environnement nvm :

```bash
source ~/.nvm/nvm.sh
claude --version
```

### Étape 4 — Vérifier l'authentification

```bash
# Test rapide : Claude doit répondre sans erreur d'authentification
echo "Bonjour" | claude
```

### Alternative : variable d'environnement directe

Si vous ne souhaitez pas utiliser `secrets.env`, exportez la variable dans votre session :

```bash
export ANTHROPIC_API_KEY=sk-ant-VOTRE_CLE_ICI
```

Pour la rendre permanente dans le profil de devuser :

```bash
echo 'export ANTHROPIC_API_KEY=sk-ant-VOTRE_CLE_ICI' >> ~/.bashrc
# ou si zsh est installé :
echo 'export ANTHROPIC_API_KEY=sk-ant-VOTRE_CLE_ICI' >> ~/.zshrc
```

---

## 3. Utiliser Claude Code au quotidien

Claude Code est un agent de développement IA en ligne de commande. Il lit votre code, comprend la structure du projet, et peut modifier des fichiers, exécuter des commandes, corriger des bugs.

### Lancer Claude Code dans un projet

```bash
su - devuser
cd /devlab-bootstrap/workspace/projects/mon-projet
claude
```

Claude Code détecte automatiquement le projet (Git, package.json, etc.).

### Commandes essentielles dans Claude Code

| Commande | Description |
|----------|-------------|
| `/help` | Aide complète |
| `/status` | État de la session |
| `/clear` | Effacer la conversation |
| `/compact` | Compresser le contexte (projet volumineux) |
| `/cost` | Voir le coût de la session |
| `Ctrl+C` | Interrompre une action en cours |
| `Ctrl+D` | Quitter Claude Code |

### Exemples d'utilisation typiques

```bash
# Démarrer sur un projet existant
cd ~/workspace/projects/mon-app
claude

# Dans Claude Code, exemples de demandes :
# "Explique-moi l'architecture de ce projet"
# "Ajoute une route POST /api/users dans src/routes/users.js"
# "Corrige le bug dans la fonction validateEmail"
# "Écris les tests pour le module auth"
# "Fais un code review du fichier src/app.js"
```

### Utiliser Claude Code de façon non-interactive (scripts)

```bash
# Passer une instruction directement
claude -p "Résume le fichier README.md en 3 points"

# Avec un fichier en entrée
cat src/app.js | claude -p "Quels sont les risques de sécurité dans ce code ?"
```

### Configurer le modèle utilisé

```bash
# Par défaut : claude-sonnet (équilibre vitesse/qualité)
# Pour des tâches complexes, utiliser opus :
claude --model claude-opus-4-7

# Pour des tâches rapides/simples :
claude --model claude-haiku-4-5-20251001
```

---

## 4. Configuration GitHub complète

### 4.1 — Ce qui a été installé par `devtools/git-github`

- **gh CLI** : outil officiel GitHub pour gérer repos, PRs, issues depuis le terminal
- **Clé SSH ed25519** : pour `git push/pull` sans mot de passe
- **Config git globale** : user.name, user.email, branche main par défaut
- **gclone** : helper pour cloner rapidement dans le workspace

### 4.2 — Configurer votre identité git

```bash
# Dans /devlab-bootstrap/config/local.env (gitignored)
nano /devlab-bootstrap/config/local.env
```

Modifier ou ajouter :

```bash
GIT_USER_NAME="Prénom Nom"
GIT_USER_EMAIL="votre@email.com"
GIT_DEFAULT_BRANCH="main"
GITHUB_USERNAME="votre-username-github"
```

Appliquer immédiatement sans réinstaller :

```bash
sudo -u devuser git config --global user.name "Prénom Nom"
sudo -u devuser git config --global user.email "votre@email.com"
```

Vérifier :

```bash
sudo -u devuser git config --global --list
```

### 4.3 — Clé SSH GitHub (déjà configurée)

La clé SSH a été générée pendant l'installation :

```bash
# Afficher la clé publique (à copier dans GitHub)
cat /home/devuser/.ssh/id_ed25519.pub
```

Pour l'ajouter à GitHub si ce n'est pas encore fait :
1. Copier le contenu de la commande ci-dessus
2. Aller sur https://github.com/settings/ssh/new
3. **Title** : `DevLab VPS` (ou autre)
4. **Key** : coller la clé publique
5. **Add SSH key**

Tester la connexion :

```bash
sudo -u devuser ssh -T git@github.com
# Réponse attendue : "Hi username! You've successfully authenticated..."
```

### 4.4 — Authentifier gh CLI

```bash
sudo -u devuser gh auth login
```

Choisir :
- **GitHub.com**
- **HTTPS** (recommandé) ou **SSH**
- Authentification par **browser** (code à saisir sur github.com/login/device) ou **token**

Avec un token (si pas de navigateur) :
1. Aller sur https://github.com/settings/tokens/new
2. Scopes requis : `repo`, `read:org`, `workflow`
3. Générer et copier le token
4. Choisir "Paste an authentication token" dans gh auth login

Vérifier :

```bash
sudo -u devuser gh auth status
```

### 4.5 — Utiliser gh CLI au quotidien

```bash
su - devuser

# Voir ses repos
gh repo list

# Créer un nouveau repo
gh repo create mon-projet --public --description "Mon projet"

# Cloner un repo
gh repo clone username/mon-projet

# Statut d'une PR
gh pr list
gh pr view 42
gh pr checkout 42

# Créer une PR
gh pr create --title "Ajout feature X" --body "Description"

# Issues
gh issue list
gh issue create --title "Bug dans login"

# Voir les workflows CI
gh run list
gh run watch
```

---

## 5. Travailler avec des projets

### Structure du workspace

```
/devlab-bootstrap/
├── workspace/
│   └── projects/          ← vos projets ici
├── repositories/          ← miroirs/archives
└── ...
```

### Cloner un projet avec gclone

```bash
su - devuser

# Cloner un repo GitHub dans workspace/projects/
gclone username/mon-repo

# Avec un nom de dossier personnalisé
gclone username/mon-repo mon-dossier
```

### Cloner manuellement

```bash
su - devuser
mkdir -p ~/workspace/projects
cd ~/workspace/projects

# Via SSH (recommandé — utilise la clé configurée)
git clone git@github.com:username/mon-repo.git

# Via HTTPS
git clone https://github.com/username/mon-repo.git
```

### Workflow typique avec Claude Code + GitHub

```bash
su - devuser
cd ~/workspace/projects/mon-repo

# 1. Créer une branche
git checkout -b feature/ma-feature

# 2. Ouvrir Claude Code pour développer
claude

# 3. Dans Claude Code : "Implémente la feature X selon les specs dans SPEC.md"
# Claude modifie les fichiers, crée les tests, etc.

# 4. Quitter Claude Code (Ctrl+D), vérifier les changements
git diff
git status

# 5. Committer
git add -A
git commit -m "feat: ajout feature X"

# 6. Pousser et créer la PR
git push origin feature/ma-feature
gh pr create --title "feat: ajout feature X" --body "Implémenté avec Claude Code"
```

---

## 6. Commandes devlab essentielles

### Vue d'ensemble

```bash
devlab status           # État du registre (modules installés/non)
devlab check            # Versions de tous les outils
devlab health           # Diagnostic complet du système
devlab list-modules     # Liste tous les modules disponibles
```

### Gestion des modules

```bash
# Installer un module spécifique
devlab install languages/nodejs
devlab install containers/docker
devlab install devtools/git-github
devlab install ai/claude-code

# Réinstaller un module (après reset)
devlab reset languages/nodejs
devlab install languages/nodejs

# Installer tous les modules activés dans modules.conf
devlab install all
```

### Maintenance

```bash
devlab backup           # Sauvegarde des configurations
devlab restore <id>     # Restaurer un backup
devlab update           # Mettre à jour le système et les outils
devlab sync             # Réconcilier registre et état réel
```

### Débogage

```bash
devlab install ai/claude-code --debug    # Mode verbeux
devlab health                             # Diagnostic détaillé
ls -lt /devlab-bootstrap/logs/errors/    # Logs d'erreurs
```

---

## 7. Les modules — utilisation quotidienne

### Node.js (languages/nodejs)

Installé via **nvm** dans le profil de devuser.

```bash
su - devuser
node --version
npm --version

# Changer de version Node.js
nvm install 22
nvm use 22
nvm alias default 22

# Versions disponibles
nvm ls
```

### Python (languages/python)

```bash
su - devuser
python3 --version
pip3 --version

# Environnement virtuel (bonne pratique)
cd mon-projet
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Docker (containers/docker)

```bash
su - devuser
docker --version
docker ps

# Lance un conteneur
docker run --rm -it ubuntu:24.04 bash

# Docker Compose
docker compose up -d
docker compose logs -f
docker compose down
```

### PostgreSQL (databases/postgresql)

```bash
# Connexion en tant que postgres
sudo -u postgres psql

# Depuis psql :
CREATE DATABASE mon_app;
CREATE USER mon_user WITH ENCRYPTED PASSWORD 'mot_de_passe';
GRANT ALL PRIVILEGES ON DATABASE mon_app TO mon_user;
\q

# Depuis devuser (si accès configuré)
psql -h 127.0.0.1 -U mon_user -d mon_app
```

Variables de connexion pour vos apps :
```
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=mon_app
DB_USER=mon_user
DB_PASS=mot_de_passe
```

### Redis (databases/redis)

```bash
# Test de connexion
redis-cli ping
# → PONG

# Utilisation basique
redis-cli set ma_cle "valeur"
redis-cli get ma_cle

# Monitor en temps réel
redis-cli monitor
```

### Nginx (web/nginx)

```bash
# Test de configuration
sudo nginx -t

# Recharger sans coupure
sudo systemctl reload nginx

# Ajouter un virtual host
sudo nano /etc/nginx/conf.d/mon-site.conf
sudo nginx -t && sudo systemctl reload nginx

# Logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### Tmux (devtools/tmux)

Indispensable sur un VPS — les sessions persistent même si la connexion SSH est coupée.

```bash
# Créer une session nommée
tmux new -s dev

# Se détacher (session reste active)
Ctrl+B puis D

# Lister les sessions
tmux ls

# Reprendre une session
tmux attach -t dev

# Dans tmux :
Ctrl+B puis C    # Nouveau fenêtre
Ctrl+B puis "    # Split horizontal
Ctrl+B puis %    # Split vertical
Ctrl+B puis N    # Fenêtre suivante
```

### Zsh + Oh My Zsh (devtools/zsh)

```bash
su - devuser
# Le shell est automatiquement zsh

# Thème et plugins configurés dans ~/.zshrc
nano ~/.zshrc

# Rechargement
source ~/.zshrc
```

---

## 8. Configuration locale et secrets

### Fichiers de configuration

| Fichier | Commité | Usage |
|---------|---------|-------|
| `config/default.env` | Oui | Valeurs par défaut — ne pas modifier |
| `config/modules.conf` | Oui | Activer/désactiver les modules |
| `config/local.env` | **Non** | Vos surcharges locales |
| `config/secrets.env` | **Non** | Clés API, mots de passe |
| `config/versions.conf` | Oui | Versions épinglées |

### Créer local.env

```bash
cp /devlab-bootstrap/config/default.env /devlab-bootstrap/config/local.env
nano /devlab-bootstrap/config/local.env
```

Paramètres importants à personnaliser :

```bash
# Identité git
GIT_USER_NAME="Votre Nom"
GIT_USER_EMAIL="votre@email.com"
GITHUB_USERNAME="votre-github"

# Versions des langages (vide = dernière stable)
NODE_VERSION="lts"
PYTHON_VERSION="3.12"
PHP_VERSION="8.3"
```

### Créer secrets.env

```bash
cat > /devlab-bootstrap/config/secrets.env << 'EOF'
# Clés API IA
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...

# Mots de passe bases de données (si personnalisés)
# POSTGRES_PASSWORD=...
EOF
chmod 600 /devlab-bootstrap/config/secrets.env
```

> **Important :** `local.env` et `secrets.env` sont dans `.gitignore` — ils ne seront jamais poussés sur GitHub. Ne mettez **jamais** de secrets dans `default.env`.

---

## 9. Ajouter un nouveau module

Si vous souhaitez ajouter un outil qui n'existe pas encore dans DevLab :

### Étape 1 — Créer le script d'installation

```bash
# Exemple : installer un outil hypothétique "monoutil"
nano /devlab-bootstrap/installers/devtools/70-monoutil.sh
```

Structure minimale :

```bash
#!/usr/bin/env bash
set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="devtools/monoutil"

source "${DEVLAB_ROOT}/lib/core.sh"
source "${DEVLAB_ROOT}/lib/packages.sh"
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "monoutil" "install"
log_section "Mon Outil"

_do_install() {
    apt_install monoutil
    log_ok "Mon outil installé"
}

installer_run \
    "devtools/monoutil" \
    "Mon Outil" \
    "monoutil --version 2>&1 | head -1" \
    "_do_install"
```

```bash
chmod +x /devlab-bootstrap/installers/devtools/70-monoutil.sh
```

### Étape 2 — Ajouter le flag dans modules.conf

```bash
nano /devlab-bootstrap/config/modules.conf
```

Ajouter :

```bash
MODULE_DEVTOOLS_MONOUTIL=true
```

### Étape 3 — Déclarer dans bin/devlab (pour install all)

Dans `bin/devlab`, dans le tableau `ordered_modules`, ajouter :

```bash
"MODULE_DEVTOOLS_MONOUTIL:devtools/70-monoutil.sh"
```

### Étape 4 — Tester

```bash
# Test d'installation directe
devlab install devtools/monoutil

# Vérifier le registre
devlab status

# Pour réinstaller (test idempotence)
devlab reset devtools/monoutil
devlab install devtools/monoutil
```

---

## Résumé — Les 5 commandes à retenir

```bash
# 1. Activer l'environnement de développement
su - devuser

# 2. Lancer Claude Code dans un projet
cd ~/workspace/projects/mon-projet && claude

# 3. Vérifier l'état du lab
devlab status

# 4. Cloner un repo GitHub
gclone username/repo

# 5. Maintenir le lab à jour
sudo devlab update
```
