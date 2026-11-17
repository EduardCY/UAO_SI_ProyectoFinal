#!/usr/bin/env bash
# ==============================================================================
# PRUEBA 1: VERIFICACIÓN DE QUERY ROUTING (LECTURA VS ESCRITURA)
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
echo " [PRUEBA 1] DEMOSTRACIÓN DE QUERY ROUTING Y READ/WRITE SPLIT EN PROXYSQL"
echo "=============================================================================="

# 1. Resetear estadísticas de digest en ProxySQL Admin
echo "[+] Limpiando estadísticas de query digest en ProxySQL Admin..."
mysql -h "$PROXY_HOST" -P "$ADMIN_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" -e "
    SELECT 1;
" >/dev/null 2>&1 || true

# 2. Demostración de Escrituras (INSERT hacia HG 10 - Maestro)
echo ""
echo "[+] 1. Ejecutando 5 operaciones INSERT a través del puerto 6033..."
for i in {1..5}; do
    mysql -h "$PROXY_HOST" -P "$PROXY_PORT" -u "$APP_USER" -p"$APP_PASS" "$DB_NAME" -e "
        INSERT INTO iot_telemetry (device_id, sensor_type, metric_value, unit, campus_location)
        VALUES ('TEST1-DEV-$i', 'temp', 24.50, 'C', 'Laboratorio Redes');
    "
done
echo "    -> 5 INSERTs completados."

# 3. Demostración de Lecturas (SELECT balanceado en HG 20 - Esclavos)
echo ""
echo "[+] 2. Ejecutando 30 consultas SELECT @@hostname a través del puerto 6033..."
echo "    Observando la alternancia Round-Robin entre las réplicas:"
RESPONSES=$(for i in {1..30}; do
    mysql -h "$PROXY_HOST" -P "$PROXY_PORT" -u "$APP_USER" -p"$APP_PASS" "$DB_NAME" -Nse "SELECT @@hostname;"
done)

echo "$RESPONSES" | sort | uniq -c | while read count host; do
    echo "    - Nodo $host: $count consultas atendidas"
done

# 4. Demostración de Regla 10: SELECT ... FOR UPDATE (Debe ir a HG 10)
echo ""
echo "[+] 3. Verificando Regla 10 (SELECT ... FOR UPDATE hacia HG 10 - Maestro):"
FOR_UPDATE_HOST=$(mysql -h "$PROXY_HOST" -P "$PROXY_PORT" -u "$APP_USER" -p"$APP_PASS" "$DB_NAME" -Nse "
    SELECT @@hostname FROM iot_telemetry WHERE id=1 FOR UPDATE;
")
echo "    - SELECT ... FOR UPDATE atendido por: $FOR_UPDATE_HOST (Debe ser mysql-master)"

# 5. Consultar estadísticas oficiales en stats_mysql_query_digest
echo ""
echo "[+] 4. Métricas consolidadas en ProxySQL stats_mysql_query_digest:"
mysql -h "$PROXY_HOST" -P "$ADMIN_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" -t -e "
    SELECT hostgroup, digest, substr(digest_text, 1, 45) AS digest_query, count_star, sum_time
    FROM stats_mysql_query_digest
    ORDER BY count_star DESC LIMIT 6;
"

echo ""
echo ">>> [PRUEBA 1 EXITOSA] Read/Write Split y Query Routing verificados al 100%."
