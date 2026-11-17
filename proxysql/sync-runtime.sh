#!/usr/bin/env bash
# ==============================================================================
# PROYECTO 4: SINCRONIZACIÓN DE NIVELES SQLITE EN PROXYSQL (RUNTIME & DISK)
# ==============================================================================
set -e

ADMIN_USER=${PROXYSQL_ADMIN_USER:-admin}
ADMIN_PASS=${PROXYSQL_ADMIN_PASSWORD:-admin}
ADMIN_PORT=${PROXYSQL_ADMIN_PORT:-6032}

echo "[PROXYSQL-SYNC] Conectando a interfaz administrativa de ProxySQL (puerto $ADMIN_PORT)..."

until mysql -h 127.0.0.1 -P "$ADMIN_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" -e "SELECT 1" >/dev/null 2>&1; do
    echo "[PROXYSQL-SYNC] Esperando inicio de ProxySQL..."
    sleep 1
done

mysql -h 127.0.0.1 -P "$ADMIN_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" <<EOSQL
-- Cargar y persistir servidores
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;

-- Cargar y persistir usuarios
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS TO DISK;

-- Cargar y persistir reglas de enrutamiento
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;

-- Cargar y persistir variables
LOAD MYSQL VARIABLES TO RUNTIME;
SAVE MYSQL VARIABLES TO DISK;
LOAD ADMIN VARIABLES TO RUNTIME;
SAVE ADMIN VARIABLES TO DISK;
EOSQL

echo "[PROXYSQL-SYNC] Servidores configurados en runtime:"
mysql -h 127.0.0.1 -P "$ADMIN_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" -t -e "SELECT hostgroup_id, hostname, port, status, weight FROM runtime_mysql_servers;"

echo "[PROXYSQL-SYNC] Reglas compiladas en runtime:"
mysql -h 127.0.0.1 -P "$ADMIN_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" -t -e "SELECT rule_id, active, destination_hostgroup, match_pattern, cache_ttl, apply FROM runtime_mysql_query_rules;"

echo "[PROXYSQL-SYNC] Sincronización MEMORY -> RUNTIME -> DISK completada exitosamente."
