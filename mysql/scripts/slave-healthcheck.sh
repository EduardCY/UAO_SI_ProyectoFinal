#!/usr/bin/env bash
# ==============================================================================
# PROYECTO 4: SCRIPT DE HEALTHCHECK PARA RÉPLICAS MYSQL (GTID & PERFORMANCE_SCHEMA)
# ==============================================================================
set -e

# 1. Comprobar que MySQL responde localmente
mysqladmin ping -u root -p"${MYSQL_ROOT_PASSWORD}" >/dev/null 2>&1 || exit 1

# 2. Comprobar estado de los hilos de replicación en performance_schema
CONN_STATE=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -Nse "SELECT SERVICE_STATE FROM performance_schema.replication_connection_status;" 2>/dev/null || true)
APPL_STATE=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -Nse "SELECT SERVICE_STATE FROM performance_schema.replication_applier_status;" 2>/dev/null || true)

if [ "$CONN_STATE" = "ON" ] && [ "$APPL_STATE" = "ON" ]; then
    exit 0
else
    echo "Replicacion no activa (Connection: $CONN_STATE, Applier: $APPL_STATE)"
    exit 1
fi
