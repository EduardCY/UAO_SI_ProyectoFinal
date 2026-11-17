#!/usr/bin/env bash
# ==============================================================================
# PROYECTO 4: ENTRYPOINT IDEMPOTENTE PARA RÉPLICAS MYSQL 8.0 (GTID + SEMI-SYNC)
# Servicios Telemáticos — Universidad Autónoma de Occidente
# ==============================================================================
set -e

# Arrancar el demonio mysqld oficial con los parámetros de comando
/usr/local/bin/docker-entrypoint.sh mysqld "$@" &
MYSQL_PID=$!

echo "[SLAVE-INIT] Esperando que mysqld local inicie completamente..."
until mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; do
    sleep 2
done
echo "[SLAVE-INIT] mysqld local activo y respondiendo."

echo "[SLAVE-INIT] Esperando conectividad TCP con mysql-master:3306..."
until mysql -h mysql-master -u repl_user -p"${MYSQL_REPL_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; do
    sleep 2
done
echo "[SLAVE-INIT] mysql-master alcanzable por red interna."

# Verificar si la replicación ya está configurada y corriendo mediante performance_schema
REPL_CONN=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -Nse "SELECT COUNT(*) FROM performance_schema.replication_connection_status WHERE SERVICE_STATE='ON';" 2>/dev/null || echo 0)
REPL_APPL=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -Nse "SELECT COUNT(*) FROM performance_schema.replication_applier_status WHERE SERVICE_STATE='ON';" 2>/dev/null || echo 0)

if [ "$REPL_CONN" -ge 1 ] && [ "$REPL_APPL" -ge 1 ]; then
    echo "[SLAVE-INIT] La replicación GTID ya se encuentra activa y sincronizada."
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SET GLOBAL read_only = 1; SET GLOBAL super_read_only = 1;" 2>/dev/null || true
else
    echo "[SLAVE-INIT] Configurando replicación GTID y plugin Semi-Síncrono..."
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "INSTALL PLUGIN rpl_semi_sync_slave SONAME 'semisync_slave.so';" 2>/dev/null || true
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOSQL
SET GLOBAL rpl_semi_sync_slave_enabled = 1;

STOP REPLICA;
RESET REPLICA;

CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='mysql-master',
  SOURCE_PORT=3306,
  SOURCE_USER='repl_user',
  SOURCE_PASSWORD='${MYSQL_REPL_PASSWORD}',
  SOURCE_AUTO_POSITION=1,
  SOURCE_CONNECT_RETRY=3,
  SOURCE_RETRY_COUNT=60;

START REPLICA;

-- Bloquear réplica en solo lectura estricta tras configurar replicación
SET GLOBAL read_only = 1;
SET GLOBAL super_read_only = 1;
EOSQL
    echo "[SLAVE-INIT] Replicación iniciada con SOURCE_AUTO_POSITION=1 y super_read_only=1 activo."
fi

# Mantener el proceso principal
wait $MYSQL_PID
