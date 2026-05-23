# Guide d'extension DevLab

## Ajouter un nouveau module

### 1. Créer l'installeur

```bash
# Convention : NN-nom.sh dans la catégorie appropriée
cat > installers/ma-categorie/60-mon-outil.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="ma-categorie/mon-outil"

source "${DEVLAB_ROOT}/lib/core.sh"
source "${DEVLAB_ROOT}/lib/packages.sh"
source "${DEVLAB_ROOT}/lib/state.sh"

log_init "mon-outil" "install"
log_section "Mon Outil"

_do_install() {
    # Votre logique d'installation ici
    apt_install mon-paquet
    log_ok "Mon Outil installé"
}

installer_run \
    "ma-categorie/mon-outil" \
    "Mon Outil" \
    "mon-outil --version 2>/dev/null" \
    "_do_install"
EOF
chmod +x installers/ma-categorie/60-mon-outil.sh
```

### 2. Ajouter au registre des modules

```bash
# Dans config/modules.conf
echo "MODULE_MA_CATEGORIE_MON_OUTIL=true" >> config/modules.conf
```

### 3. Enregistrer dans le dispatcher

Dans `bin/devlab`, ajouter dans la `declare -A module_map` :
```bash
["MODULE_MA_CATEGORIE_MON_OUTIL"]="ma-categorie/60-mon-outil.sh"
```

### 4. Tester

```bash
devlab install ma-categorie/mon-outil --dry-run
devlab install ma-categorie/mon-outil
devlab sync
```

## Structure d'un installeur correct

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Autodétection DEVLAB_ROOT
DEVLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVLAB_ROOT DEVLAB_MODULE="categorie/outil"

# 2. Sources des bibliothèques
source "${DEVLAB_ROOT}/lib/core.sh"
source "${DEVLAB_ROOT}/lib/packages.sh"
source "${DEVLAB_ROOT}/lib/state.sh"

# 3. Initialisation log
log_init "outil" "install"

# 4. Fonction d'installation encapsulée
_do_install() {
    # Vérifications de prérequis
    # Logique d'installation
    # Tests de sanité (non bloquants)
}

# 5. Appel via installer_run (gère idempotence + registre)
installer_run \
    "categorie/outil" \
    "Label affiché" \
    "commande --version" \
    "_do_install"
```

## Règles d'idempotence

Chaque opération dans `_do_install` doit vérifier avant d'agir :

```bash
# ✅ Bon : vérifie avant
if ! command_exists mon-outil; then
    # installer
fi

# ✅ Bon : apt_install est idempotent
apt_install mon-paquet

# ❌ Mauvais : s'exécute à chaque fois
curl ... | bash

# ✅ Bon : télécharge seulement si absent
if [[ ! -f /usr/local/bin/mon-outil ]]; then
    curl ...
fi
```

## Ajouter une catégorie

```bash
mkdir -p installers/ma-nouvelle-categorie/
# Créer les scripts d'installation
# Ajouter les MODULE_* dans config/modules.conf
# Enregistrer dans bin/devlab
```

## Templates de configuration

Créer un template dans `configs/` :
```bash
# configs/mon-outil/config.conf.tpl
# Utilise les variables d'environnement de config/default.env
PORT=${MON_OUTIL_PORT}
USER=${DEVLAB_USER}
```

Dans l'installeur, utiliser :
```bash
render_template "${DEVLAB_ROOT}/configs/mon-outil/config.conf.tpl" "/etc/mon-outil/config.conf"
```
