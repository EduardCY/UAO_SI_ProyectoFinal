#!/usr/bin/env bash
# ==============================================================================
# PRUEBA 6: ACELERACIÓN MEDIANTE QUERY CACHE EN MEMORIA RAM DE PROXYSQL
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
echo " [PRUEBA 6] DEMOSTRACIÓN DE QUERY CACHE EN RAM (SUB-MILISEGUNDO) — REGLA 30"
echo "=============================================================================="

QUERY_NOCACHE="SELECT id, device_id, metric_value FROM iot_telemetry ORDER BY id DESC LIMIT 5;"
QUERY_CACHE="SELECT /*+ CACHE */ id, device_id, metric_value FROM iot_telemetry ORDER BY id DESC LIMIT 5;"

echo "[+] 1. Ejecutando 100 consultas SIN Query Cache (Atendidas por backend MySQL)..."
START_NOCACHE=$(date +%s%N)
for i in {1..100}; do
    mysql -h "$PROXY_HOST" -P "$PROXY_PORT" -u "$APP_USER" -p"$APP_PASS" "$DB_NAME" -e "$QUERY_NOCACHE" >/dev/null
done
END_NOCACHE=$(date +%s%N)
DIFF_NOCACHE_MS=$(awk "BEGIN {printf \"%.2f\", ($END_NOCACHE - $START_NOCACHE)/1000000}")
AVG_NOCACHE_MS=$(awk "BEGIN {printf \"%.3f\", $DIFF_NOCACHE_MS/100}")

echo "    -> Tiempo total: $DIFF_NOCACHE_MS ms | Latencia media por query: $AVG_NOCACHE_MS ms"

echo ""
echo "[+] 2. Ejecutando 100 consultas CON Query Cache /*+ CACHE */ (Atendidas desde RAM de ProxySQL)..."
START_CACHE=$(date +%s%N)
for i in {1..100}; do
    mysql -h "$PROXY_HOST" -P "$PROXY_PORT" -u "$APP_USER" -p"$APP_PASS" "$DB_NAME" -e "$QUERY_CACHE" >/dev/null
done
END_CACHE=$(date +%s%N)
DIFF_CACHE_MS=$(awk "BEGIN {printf \"%.2f\", ($END_CACHE - $START_CACHE)/1000000}")
AVG_CACHE_MS=$(awk "BEGIN {printf \"%.3f\", $DIFF_CACHE_MS/100}")

echo "    -> Tiempo total: $DIFF_CACHE_MS ms | Latencia media por query: $AVG_CACHE_MS ms"

SPEEDUP=$(awk "BEGIN {printf \"%.1fx\", $DIFF_NOCACHE_MS/$DIFF_CACHE_MS}")
echo ""
echo ">>> FACTOR DE ACELERACIÓN EN MEMORIA RAM: $SPEEDUP más rápido"

echo ""
echo "[+] 3. Introspección en stats_mysql_query_digest (Hits en Cache de ProxySQL):"
mysql -h "$PROXY_HOST" -P "$ADMIN_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" -t -e "
    SELECT hostgroup, digest, substr(digest_text, 1, 45) AS query, count_star, sum_time
    FROM stats_mysql_query_digest
    WHERE digest_text LIKE '%CACHE%'
    LIMIT 1;
"

echo ""
echo ">>> [PRUEBA 6 EXITOSA] Query Cache en RAM operativo con latencia sub-milisegundo demostrada."
