# Redis configuration — DevLab
# Généré par DevLab Bootstrap

bind ${REDIS_BIND}
port ${REDIS_PORT}
protected-mode yes

# Persistance
save 900 1
save 300 10
save 60 10000
dbfilename dump.rdb
dir /var/lib/redis

# Logs
loglevel notice
logfile /var/log/redis/redis-server.log

# Limites mémoire
maxmemory 256mb
maxmemory-policy allkeys-lru

# Sécurité — désactiver commandes dangereuses
rename-command FLUSHALL ""
rename-command FLUSHDB ""
rename-command DEBUG ""
rename-command CONFIG DEVLAB_REDIS_CONFIG

# Performance
tcp-backlog 511
timeout 0
tcp-keepalive 300
