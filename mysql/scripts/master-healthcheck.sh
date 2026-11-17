#!/usr/bin/env bash
# ==============================================================================
# PROYECTO 4: SCRIPT DE HEALTHCHECK PARA MAESTRO MYSQL (ZERO-FLAKE)
# ==============================================================================
set -e

# 1. Comprobar que responde mysqladmin ping
mysqladmin ping -u root -p"${MYSQL_ROOT_PASSWORD}" >/dev/null 2>&1 || exit 1

# 2. Comprobar que cluster_app ya puede autenticar por TCP y consultar la tabla de telemetria
# Esto neutraliza el falso positivo del servidor temporal de MySQL en initdb.d
mysql -h 127.0.0.1 -u cluster_app -p"${MYSQL_APP_PASSWORD:-AppPassword2026!}" -e "SELECT 1 FROM telematicos_db.iot_telemetry LIMIT 1;" >/dev/null 2>&1 || exit 1

exit 0
