# Guide de maintenance DevLab

## Mise à jour du système

```bash
# Mise à jour complète (APT + Node + Python + Rust + OMZ)
sudo devlab update

# Mise à jour APT uniquement
sudo apt update && sudo apt upgrade
```

## Sauvegardes

```bash
# Backup complet des configurations
devlab backup

# Les backups sont dans backups/configs/
ls -lt /devlab/backups/configs/

# Rotation automatique : 10 derniers conservés
```

## Restauration

```bash
# Lister les backups disponibles
ls /devlab/backups/configs/*.tar.gz

# Restaurer
sudo devlab restore devlab-backup-20260523_143022.tar.gz
```

## Synchronisation du registre

```bash
# Si vous avez installé des outils manuellement
devlab sync

# Le registre reflètera l'état réel
devlab status
```

## Logs

```bash
# Logs d'installation
ls -lt /devlab/logs/install/

# Logs d'erreurs seulement
ls -lt /devlab/logs/errors/

# Logs de maintenance
ls -lt /devlab/logs/maintenance/

# Voir un log spécifique
cat /devlab/logs/install/YYYYMMDD_HHMMSS_nodejs.log
```

## Nettoyage des logs

```bash
# Supprimer les logs de plus de 30 jours
find /devlab/logs -name "*.log" -mtime +30 -delete

# Vider les logs d'erreur (après investigation)
rm -f /devlab/logs/errors/*.log
```

## Réinstaller un module

```bash
# 1. Retirer du registre
devlab reset languages/nodejs

# 2. Réinstaller
devlab install languages/nodejs

# 3. Vérifier
devlab check
```

## Diagnostic

```bash
# Diagnostic complet
devlab health

# État des services
systemctl status nginx postgresql redis-server docker

# Ports ouverts
ss -tlnp

# Ressources
free -h
df -h
htop
```

## Gestion des services

```bash
# Nginx
sudo systemctl restart nginx
sudo nginx -t                    # Tester la config

# PostgreSQL
sudo systemctl restart postgresql
sudo -u postgres psql            # Console

# Redis
sudo systemctl restart redis-server
redis-cli ping                   # Tester

# Docker
sudo systemctl restart docker
docker ps                        # Conteneurs actifs
```

## Sauvegarde PostgreSQL manuelle

```bash
# Dump de toutes les bases
sudo -u postgres pg_dumpall | gzip > backup-$(date +%Y%m%d).sql.gz

# Dump d'une base spécifique
sudo -u postgres pg_dump devlab | gzip > devlab-$(date +%Y%m%d).sql.gz

# Restauration
gunzip -c backup.sql.gz | sudo -u postgres psql
```
