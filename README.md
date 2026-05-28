# DevLab — AI Development Laboratory Bootstrap System

Système de déploiement automatisé d'un laboratoire de développement web IA sur Ubuntu Server 24.04 LTS.

## Philosophie

DevLab n'est pas un script d'installation — c'est un **firmware de laboratoire** : un ensemble de couches modulaires qui transforment un VPS vierge en environnement de développement reproductible, idempotent et maintenable.

**Trois invariants :**
- **Idempotent** : ré-exécutable sans casser l'existant
- **Modulaire** : chaque outil s'installe indépendamment
- **Versionnable** : clonable et reconstructible sur n'importe quel VPS

## Démarrage rapide

```bash
# 1. Cloner le dépôt (n'importe où sur le serveur)
git clone https://github.com/zumradeals/ia-dev.git /devlab-bootstrap
cd /devlab-bootstrap

# 2. Premier lancement : setup.sh configure le PATH et lance le bootstrap
#    (setup.sh détecte automatiquement DEVLAB_ROOT depuis son emplacement)
sudo bash setup.sh

# Après le bootstrap, devlab est disponible dans le PATH
# 3. Installer les modules (depuis n'importe quel répertoire)
devlab install all                      # Tous les modules activés
devlab install languages/nodejs         # Module spécifique

# 4. Vérifier
devlab status
devlab health
```

> **Note** : `sudo bash setup.sh` est la **seule commande root** nécessaire au premier lancement.
> Elle crée `/usr/local/bin/devlab` et configure `DEVLAB_ROOT` automatiquement.
> Ensuite, tout s'utilise via `devlab <commande>` sans chemin explicite.

## Structure

```
/devlab/
├── bin/devlab              CLI principal
├── bootstrap/              Bootstrap système (root, une fois)
├── lib/                    Bibliothèque shell réutilisable
├── installers/             Modules d'installation
│   ├── base/
│   ├── languages/
│   ├── containers/
│   ├── databases/
│   ├── web/
│   ├── ai/
│   ├── devtools/
│   └── testing/
├── configs/                Templates de configuration
├── config/                 Configuration DevLab
├── state/                  Registre d'état (auto-généré)
├── scripts/                Scripts opérationnels
├── docker/stacks/          Stacks Docker Compose prêtes
├── workspace/              Projets actifs
├── logs/                   Tous les logs
└── docs/                   Documentation complète
```

## Configuration

```bash
# Copier et éditer la configuration locale
cp config/default.env config/local.env
nano config/local.env

# Activer/désactiver des modules
nano config/modules.conf

# Secrets (jamais commités)
cp config/secrets.env.example config/secrets.env
nano config/secrets.env
```

## Commandes

| Commande | Description |
|----------|-------------|
| `devlab bootstrap` | Bootstrap initial (root) |
| `devlab install all` | Installer tous les modules activés |
| `devlab install <module>` | Installer un module spécifique |
| `devlab status` | Vue d'ensemble du registre |
| `devlab check` | Versions des outils installés |
| `devlab health` | Diagnostic complet |
| `devlab update` | Mettre à jour le système |
| `devlab backup` | Sauvegarder les configurations |
| `devlab sync` | Réconcilier registre ↔ système |
| `devlab reset <module>` | Réinitialiser un module |

## Documentation

- [Architecture](docs/architecture.md)
- [Installation](docs/installation.md)
- [Usage](docs/usage.md)
- [Maintenance](docs/maintenance.md)
- [Sécurité](docs/security.md)
- [Extension](docs/extension.md)

## Cible

- Ubuntu Server 24.04 LTS
- VPS cloud, bare metal, VM, machine locale
- Architecture x86_64 (ARM64 : support partiel)
