#!/usr/bin/env bash
# ==============================================================================
# PRUEBA 3: BENCHMARK SYSBENCH (1M FILAS, 16 HILOS, 120s) COMPARATIVO
# Proyecto 4: Balanceo de Cargas MySQL con ProxySQL — UAO
# Autores: Felipe Charria Caicedo & Eduard Criollo Yule
# ==============================================================================
set -e

TABLE_SIZE=${SYSBENCH_TABLE_SIZE:-1000000}
THREADS=${SYSBENCH_THREADS:-16}
DURATION=${SYSBENCH_TIME:-120}
TABLES=${SYSBENCH_TABLES:-1}

APP_USER=${MYSQL_APP_USER:-cluster_app}
APP_PASS=${MYSQL_APP_PASSWORD:-AppPassword2026!}
DB_NAME="sbtest"

RESULTS_DIR="/workspace/results"
mkdir -p "$RESULTS_DIR"

echo "=============================================================================="
echo " [PRUEBA 3] BENCHMARK SYSBENCH COMPARATIVO (DIRECTO VS PROXYSQL)"
echo " Parámetros: 1 Tabla de $TABLE_SIZE filas | $THREADS Hilos | $DURATION Segundos"
echo "=============================================================================="

# 1. Preparar dataset en mysql-master (se replica automáticamente a los esclavos)
echo "[+] 1. Preparando tabla de pruebas ($TABLE_SIZE registros) en MySQL Master..."
sysbench /usr/share/sysbench/oltp_common.lua \
    --mysql-host=mysql-master \
    --mysql-port=3306 \
    --mysql-user="$APP_USER" \
    --mysql-password="$APP_PASS" \
    --mysql-db="$DB_NAME" \
    --tables="$TABLES" \
    --table-size="$TABLE_SIZE" \
    cleanup >/dev/null 2>&1 || true

sysbench /usr/share/sysbench/oltp_common.lua \
    --mysql-host=mysql-master \
    --mysql-port=3306 \
    --mysql-user="$APP_USER" \
    --mysql-password="$APP_PASS" \
    --mysql-db="$DB_NAME" \
    --tables="$TABLES" \
    --table-size="$TABLE_SIZE" \
    prepare

echo "[+] Dataset preparado. Esperando 5 segundos para sincronización GTID completa..."
sleep 5

# Archivo de salida consolidado CSV
CSV_FILE="$RESULTS_DIR/benchmark_metrics.csv"
echo "scenario,target,threads,duration_sec,tps,qps,lat_avg_ms,lat_p95_ms,lat_p99_ms" > "$CSV_FILE"

run_and_parse() {
    local scenario=$1
    local target_host=$2
    local target_port=$3
    local label=$4
    local lua_script="/usr/share/sysbench/${scenario}.lua"
    local log_file="$RESULTS_DIR/sysbench_${label}_${scenario}.log"

    echo ""
    echo "------------------------------------------------------------------------------"
    echo "[*] Ejecutando: $label ($scenario) en ${target_host}:${target_port}..."
    echo "------------------------------------------------------------------------------"

    sysbench "$lua_script" \
        --mysql-host="$target_host" \
        --mysql-port="$target_port" \
        --mysql-user="$APP_USER" \
        --mysql-password="$APP_PASS" \
        --mysql-db="$DB_NAME" \
        --tables="$TABLES" \
        --table-size="$TABLE_SIZE" \
        --threads="$THREADS" \
        --time="$DURATION" \
        --report-interval=10 \
        run | tee "$log_file"

    local tps=$(grep -E "transactions:" "$log_file" | awk -F'(' '{print $2}' | awk '{print $1}')
    local qps=$(grep -E "queries:" "$log_file" | awk -F'(' '{print $2}' | awk '{print $1}')
    local lat_avg=$(grep -E "avg:" "$log_file" | awk '{print $2}')
    local lat_p95=$(grep -E "95th percentile:" "$log_file" | awk '{print $3}')
    local lat_p99=$(grep -E "99th percentile:" "$log_file" | awk '{print $3}' || echo "N/A")

    echo "$scenario,$label,$THREADS,$DURATION,$tps,$qps,$lat_avg,$lat_p95,$lat_p99" >> "$CSV_FILE"

    echo ">>> RESULTADOS $label:"
    echo "    - TPS: $tps trans/seg"
    echo "    - QPS: $qps queries/seg"
    echo "    - Latencia media: $lat_avg ms | Percentil 95: $lat_p95 ms"
}

# 2. Benchmark oltp_read_only: Conexión Directa a Master vs Clúster con ProxySQL
run_and_parse "oltp_read_only" "mysql-master" "3306" "Directo_Master"
run_and_parse "oltp_read_only" "proxysql" "6033" "Cluster_ProxySQL"

# 3. Benchmark oltp_read_write: Conexión Directa vs ProxySQL
run_and_parse "oltp_read_write" "mysql-master" "3306" "Directo_Master"
run_and_parse "oltp_read_write" "proxysql" "6033" "Cluster_ProxySQL"

echo ""
echo "=============================================================================="
echo " RESUMEN FINAL DE MÉTRICAS EXPORTADAS EN $CSV_FILE"
echo "=============================================================================="
cat "$CSV_FILE"

echo ""
echo ">>> [PRUEBA 3 EXITOSA] Benchmark Sysbench completado y exportado para informe IEEE."
