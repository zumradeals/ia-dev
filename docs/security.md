# Sécurité DevLab

## Modèle de sécurité

DevLab applique le principe du **moindre privilège** à chaque couche :

1. Le bootstrap s'exécute en root (nécessaire pour la configuration système)
2. Les installeurs de modules s'exécutent en tant que `devuser` autant que possible
3. Les secrets ne transitent jamais dans les logs

## Gestion des secrets

### Fichiers concernés

| Fichier | Contenu | Git | Permissions |
|---------|---------|-----|-------------|
| `config/secrets.env` | API keys, mots de passe | Ignoré | 600 |
| `config/local.env` | Config locale | Ignoré | 644 |
| `config/default.env` | Valeurs par défaut | Commité | 644 |

### Vérification

```bash
# Vérifier que secrets.env n'est pas commité
git ls-files config/secrets.env   # Doit retourner vide

# Vérifier les permissions
ls -la config/secrets.env          # Doit afficher -rw-------
```

### Template secrets.env

```bash
cat > config/secrets.env << 'EOF'
# Secrets DevLab — NE JAMAIS COMMITTER
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
POSTGRES_DEVUSER_PASSWORD=
REDIS_PASSWORD=
CODE_SERVER_PASSWORD=
EOF
chmod 600 config/secrets.env
```

## Pare-feu UFW

Par défaut, UFW est configuré avec :
- Politique entrante : **DENY ALL**
- Politique sortante : **ALLOW ALL**
- Ouvertures : 22 (SSH), 80 (HTTP), 443 (HTTPS)

```bash
# Voir l'état
sudo ufw status numbered

# Ajouter un port
sudo ufw allow 8080/tcp

# Supprimer une règle
sudo ufw delete <numéro>
```

## SSH Hardening

Configuration appliquée par `bootstrap/20-security.sh` :

```
PermitRootLogin no
PasswordAuthentication no     # Clé SSH uniquement
MaxAuthTries 3
X11Forwarding no
PermitEmptyPasswords no
Protocol 2
LoginGraceTime 30
```

**Important** : `PasswordAuthentication no` signifie que vous devez avoir une clé SSH configurée **avant** le bootstrap sécurité.

```bash
# Copier votre clé publique
ssh-copy-id -i ~/.ssh/id_rsa.pub devuser@votre-vps
# Ou manuellement
cat ~/.ssh/id_rsa.pub >> /home/devuser/.ssh/authorized_keys
chmod 600 /home/devuser/.ssh/authorized_keys
```

## Fail2ban

Configuré sur SSH avec :
- `maxretry = 3` tentatives
- `bantime = 86400` secondes (24h)
- `findtime = 600` secondes (10min)

```bash
# Voir les IPs bannies
sudo fail2ban-client status sshd

# Débannir une IP
sudo fail2ban-client set sshd unbanip 1.2.3.4
```

## Audit de sécurité

```bash
# Vérifier les ports ouverts
ss -tlnp

# Vérifier les processus root
ps aux | grep root

# Vérifier sudo
sudo -l

# Audit fail2ban
sudo fail2ban-client status

# Vérifier UFW
sudo ufw status verbose
```

## Risques connus et mitigations

| Risque | Mitigation |
|--------|-----------|
| code-server exposé | Désactivé par défaut, auth password, bind 127.0.0.1 uniquement |
| Bases de données accessibles | Bind sur 127.0.0.1 par défaut |
| Redis FLUSHALL | Commande renommée/désactivée |
| Docker socket | Groupe docker limité à devuser |
| Clés API dans les logs | Masquage automatique dans lib/core.sh |
