#!/usr/bin/env bash
# ==============================================================================
# SCRIPT MAESTRO DE DEMOSTRACIÓN DE LAS 8 PRUEBAS (SUSTENTACIÓN 20 MIN)
# Proyecto 4: Balanceo de Cargas MySQL con ProxySQL — UAO
# Autores: Felipe Charria Caicedo & Eduard Criollo Yule
# ==============================================================================
set -e

echo "=============================================================================="
echo "    UNIVERSIDAD AUTÓNOMA DE OCCIDENTE — SERVICIOS TELEMÁTICOS (2026-02)"
echo "    PROYECTO 4: CLÚSTER MYSQL 8.0 & BALANCEO INTELIGENTE CON PROXYSQL 2.x"
echo "    Ingenieros: Felipe Charria Caicedo & Eduard Criollo Yule"
echo "=============================================================================="
echo ""

# Ejecución secuencial de las 8 pruebas
bash /workspace/scripts/test1_query_routing.sh proxysql
echo ""
sleep 2

bash /workspace/scripts/test2_master_failover.sh proxysql
echo ""
sleep 2

# Para la corrida completa automatizada se usa tiempo representativo o el configurado
bash /workspace/scripts/test3_sysbench_benchmark.sh
echo ""
sleep 2

bash /workspace/scripts/test4_connection_pooling.sh proxysql
echo ""
sleep 2

bash /workspace/scripts/test5_hot_scale_slave3.sh proxysql
echo ""
sleep 2

bash /workspace/scripts/test6_query_cache.sh proxysql
echo ""
sleep 2

bash /workspace/scripts/test7_flask_e2e.sh app-flask
echo ""
sleep 2

bash /workspace/scripts/test8_tls_security.sh proxysql
echo ""
sleep 2

bash /workspace/scripts/test9_parametric_scenarios.sh proxysql
echo ""

echo "=============================================================================="
echo " >>> BATERÍA DE 9 PRUEBAS EJECUTADA CON ÉXITO — PROTOTIPO 100% OPERATIVO <<<"
echo "=============================================================================="
