# Architecture DevLab

## Vue d'ensemble

```
┌─────────────────────────────────────────────────────────┐
│                     bin/devlab                          │
│               (CLI dispatcher — point d'entrée)         │
└────────────────────────┬────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
  ┌──────────┐    ┌───────────┐    ┌──────────────┐
  │ lib/     │    │ config/   │    │ state/       │
  │ core.sh  │    │ *.env     │    │ registry.json│
  │ state.sh │    │ modules   │    │              │
  │ checks.sh│    │ versions  │    │ Source de    │
  │ packages │    │           │    │ vérité       │
  └──────────┘    └───────────┘    └──────────────┘
        │
        ▼
  ┌─────────────────────────────────────────────┐
  │              installers/                    │
  │  base/    languages/   containers/          │
  │  web/     databases/   ai/                  │
  │  devtools/ testing/                         │
  └─────────────────────────────────────────────┘
        │
        ▼
  ┌─────────────┐    ┌──────────┐    ┌─────────┐
  │  configs/   │    │ scripts/ │    │  logs/  │
  │  templates  │    │ opérat.  │    │ traçab. │
  └─────────────┘    └──────────┘    └─────────┘
```

## Couches du système

### Couche 0 : Bootstrap (bootstrap/)
- S'exécute en root, une seule fois
- Configure le système de base : APT, sécurité, utilisateurs
- Crée l'arborescence /devlab/
- Initialise le registre d'état

### Couche 1 : Bibliothèque (lib/)
- `core.sh` : logging, couleurs, utilitaires universels
- `state.sh` : lecture/écriture du registre JSON
- `checks.sh` : détection de versions et services
- `packages.sh` : wrappers idempotents APT/npm/pip/cargo
- `security.sh` : fonctions UFW, SSH, Fail2ban

### Couche 2 : Configuration (config/)
- `default.env` : valeurs par défaut (versionné)
- `local.env` : surcharges locales (gitignored)
- `secrets.env` : API keys (gitignored, chmod 600)
- `modules.conf` : activation/désactivation modules
- `versions.conf` : versions épinglées

### Couche 3 : Installeurs (installers/)
- Modules indépendants, ordonnés par numéro
- Chacun sourcé lib/core.sh + lib/state.sh
- Utilise `installer_run` pour l'idempotence automatique
- Enregistre le résultat dans state/registry.json

### Couche 4 : Registre d'état (state/)
- `registry.json` : source de vérité de ce qui est installé
- Consulté avant chaque installation
- Mis à jour après chaque installation
- Réconciliable via `devlab sync`

### Couche 5 : Configuration système (configs/)
- Templates avec variables `${VAR}` (substitution via envsubst)
- Un répertoire par service
- Appliqués lors de l'installation ou sur demande

### Couche 6 : Scripts opérationnels (scripts/)
- Maintenance courante (update, backup, restore)
- Diagnostic (health, status, sync)

## Modèle d'idempotence

```
installer_run(module_key, label, version_cmd, install_fn)
       │
       ├── state_is_installed(module_key) ?
       │       YES → log_skip → exit 0
       │
       └── NO → install_fn()
               │
               ├── SUCCESS → state_set(key, version, "installed")
               └── FAILURE → state_set_failed(key, reason)
                             log_error → exit $code
```

## Flux d'exécution complet

```
VPS vierge Ubuntu 24.04
        │
        ▼
bootstrap/00-preflight.sh   ← Vérifications (read-only)
        │
        ▼
bootstrap/10-base-packages.sh ← APT base (jq, git, curl...)
        │
        ▼
bootstrap/20-security.sh    ← UFW, Fail2ban, SSH
        │
        ▼
bootstrap/30-users-groups.sh ← devuser, groupe devlab
        │
        ▼
bootstrap/40-directories.sh ← Arborescence + registre
        │
        ▼
installers/* (selon modules.conf)
        │
        ▼
scripts/health.sh            ← Rapport final
        │
        ▼
Laboratoire opérationnel ✓
```

## Conventions de nommage

| Élément | Format | Exemple |
|---------|--------|---------|
| Scripts | `NN-kebab-case.sh` | `10-nodejs.sh` |
| Fonctions | `verb_noun` snake_case | `install_package` |
| Variables globales | `UPPER_SNAKE_CASE` | `DEVLAB_ROOT` |
| Variables locales | `lower_snake_case` | `pkg_name` |
| Clés registre | `categorie/outil` | `languages/nodejs` |
| Flags modules | `MODULE_CAT_NOM` | `MODULE_LANGUAGES_NODEJS` |
| Logs | `YYYYMMDD_HHMMSS_module.log` | `20260523_143022_docker.log` |
