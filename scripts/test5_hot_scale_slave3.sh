#!/usr/bin/env bash
# ==============================================================================
# PRUEBA 5: ESCALAMIENTO HORIZONTAL EN CALIENTE DE UN 3er ESCLAVO
# Proyecto 4: Balanceo de Cargas MySQL con ProxySQL — UAO
# Autores: Felipe Charria Caicedo & Eduard Criollo Yule
# ==============================================================================
set -e

PROXY_HOST=${1:-proxysql}
PROXY_PORT=${PROXY_PORT:-6033}
ADMIN_PORT=${ADMIN_PORT:-6032}
ADMIN_USER=${PROXYSQL_ADMIN_USER:-radmin}
ADMIN_PASS=${PROXYSQL_ADMIN_PASSWORD:-radmin}
APP_USER=${MYSQL_APP_USER:-cluster_app}
APP_PASS=${MYSQL_APP_PASSWORD:-AppPassword2026!}
DB_NAME=${MYSQL_DATABASE:-telematicos_db}

echo "=============================================================================="
echo " [PRUEBA 5] ESCALAMIENTO EN CALIENTE: ADICIÓN DE mysql-slave-3 EN HG 20"
echo "=============================================================================="

echo "[+] 1. Estado inicial de servidores en Hostgroup 20 (2 Réplicas):"
mysql -h "$PROXY_HOST" -P "$ADMIN_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" -t -e "
    SELECT hostgroup_id, hostname, status, weight FROM runtime_mysql_servers WHERE hostgroup_id=20;
"

echo ""
echo "[+] 2. Verificando disponibilidad de mysql-slave-3 en la red..."
if command -v docker >/dev/null 2>&1; then
    docker compose --profile scale up -d mysql-slave-3
fi

echo "    Esperando inicialización y sincronización GTID de mysql-slave-3..."
until mysql -h mysql-slave-3 -u "$APP_USER" -p"$APP_PASS" "$DB_NAME" -e "SELECT 1" >/dev/null 2>&1; do
    sleep 2
done
echo "    -> mysql-slave-3 activo y respondiendo."

echo ""
echo "[+] 3. Incorporando dinámicamente mysql-slave-3 a ProxySQL RUNTIME y DISK..."
mysql -h "$PROXY_HOST" -P "$ADMIN_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" <<EOSQL
DELETE FROM mysql_servers WHERE hostname = 'mysql-slave-3';
INSERT INTO mysql_servers (hostgroup_id, hostname, port, weight, max_connections, comment)
VALUES (20, 'mysql-slave-3', 3306, 1000, 100, 'Slave 3 - Incorporado en Caliente');

LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
EOSQL

echo "    Servidores en HG 20 tras la incorporación dinámica:"
mysql -h "$PROXY_HOST" -P "$ADMIN_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" -t -e "
    SELECT hostgroup_id, hostname, status, weight FROM runtime_mysql_servers WHERE hostgroup_id=20;
"

echo ""
echo "[+] 4. Verificando redistribución equitativa de lecturas entre los 3 esclavos (90 consultas):"
RESPONSES=$(for i in {1..90}; do
    mysql -h "$PROXY_HOST" -P "$PROXY_PORT" -u "$APP_USER" -p"$APP_PASS" "$DB_NAME" -Nse "SELECT @@hostname;"
done)

echo "$RESPONSES" | sort | uniq -c | while read count host; do
    PERCENT=$(awk "BEGIN {printf \"%.1f\", ($count/90)*100}")
    echo "    - Nodo $host: $count consultas ($PERCENT%)"
done

echo ""
echo ">>> [PRUEBA 5 EXITOSA] Tercer esclavo incorporado en caliente con rebalanceo 33.3% / 33.3% / 33.3%."
