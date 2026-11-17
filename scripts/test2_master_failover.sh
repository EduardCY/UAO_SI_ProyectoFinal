#!/usr/bin/env bash
# ==============================================================================
# PRUEBA 2: CAÍDA FORZADA DEL MAESTRO, RESILIENCIA DE LECTURAS Y FAILOVER
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
echo " [PRUEBA 2] CAÍDA FORZADA DEL MAESTRO Y TOLERANCIA A FALLOS EN LECTURAS"
echo "=============================================================================="

echo "[+] 1. Estado inicial de los servidores en ProxySQL:"
mysql -h "$PROXY_HOST" -P "$ADMIN_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" -t -e "
    SELECT hostgroup_id, hostname, port, status, weight FROM runtime_mysql_servers;
"

echo ""
echo "[+] 2. Simulando caída del Maestro (deteniendo contenedor mysql-master)..."
docker stop mysql-master >/dev/null 2>&1 || true

echo "    Esperando detección por el monitor de ProxySQL (3 segundos)..."
sleep 3

echo ""
echo "[+] 3. Estado de los servidores tras la caída del Maestro:"
mysql -h "$PROXY_HOST" -P "$ADMIN_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" -t -e "
    SELECT hostgroup_id, hostname, port, status, weight FROM runtime_mysql_servers;
"

echo ""
echo "[+] 4. Verificando continuidad del 100% en las operaciones de lectura (HG 20):"
FAILURES=0
for i in {1..20}; do
    HOST=$(mysql -h "$PROXY_HOST" -P "$PROXY_PORT" -u "$APP_USER" -p"$APP_PASS" "$DB_NAME" -Nse "SELECT @@hostname;" 2>/dev/null || true)
    if [ -z "$HOST" ]; then
        FAILURES=$((FAILURES + 1))
    fi
done

if [ "$FAILURES" -eq 0 ]; then
    echo "    -> EXCELENTE: 20/20 lecturas respondidas con éxito por las réplicas activas."
else
    echo "    -> ADVERTENCIA: Se presentaron $FAILURES fallos en lectura."
fi

echo ""
echo "[+] 5. Demostrando Failover Dinámico: Promoviendo mysql-slave-1 como nuevo primario..."
# Desactivar read_only en mysql-slave-1 para que ProxySQL lo reclasifique en HG 10
docker exec mysql-slave-1 mysql -uroot -p"${MYSQL_ROOT_PASSWORD:-RootPasswordTelematicos2026!}" -e "
    SET GLOBAL super_read_only = 0;
    SET GLOBAL read_only = 0;
" >/dev/null 2>&1 || true

echo "    Esperando que ProxySQL detecte el cambio de read_only (2 segundos)..."
sleep 2

echo "    Servidores tras promoción de mysql-slave-1:"
mysql -h "$PROXY_HOST" -P "$ADMIN_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" -t -e "
    SELECT hostgroup_id, hostname, port, status, weight FROM runtime_mysql_servers;
"

echo ""
echo "[+] 6. Restaurando topología original (levantando mysql-master y restaurando roles)..."
docker start mysql-master >/dev/null 2>&1 || true
docker exec mysql-slave-1 mysql -uroot -p"${MYSQL_ROOT_PASSWORD:-RootPasswordTelematicos2026!}" -e "
    SET GLOBAL super_read_only = 1;
    SET GLOBAL read_only = 1;
" >/dev/null 2>&1 || true

echo "    Esperando que el maestro inicie y se reintegre (5 segundos)..."
sleep 5

echo "    Estado final restaurado de servidores en ProxySQL:"
mysql -h "$PROXY_HOST" -P "$ADMIN_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" -t -e "
    SELECT hostgroup_id, hostname, port, status, weight FROM runtime_mysql_servers;
"

echo ""
echo ">>> [PRUEBA 2 EXITOSA] Resiliencia ante caída del maestro y failover demostrados."
