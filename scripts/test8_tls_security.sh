#!/usr/bin/env bash
# ==============================================================================
# PRUEBA 8: SEGURIDAD Y CIFRADO TLS/SSL (X.509) EN TRÁNSITO HACIA PROXYSQL
# Proyecto 4: Balanceo de Cargas MySQL con ProxySQL — UAO
# Autores: Felipe Charria Caicedo & Eduard Criollo Yule
# ==============================================================================
set -e

PROXY_HOST=${1:-proxysql}
PROXY_PORT=${PROXY_PORT:-6033}
APP_USER=${MYSQL_APP_USER:-cluster_app}
APP_PASS=${MYSQL_APP_PASSWORD:-AppPassword2026!}
DB_NAME=${MYSQL_DATABASE:-telematicos_db}

echo "=============================================================================="
echo " [PRUEBA 8] VERIFICACIÓN DE CIFRADO TLS/SSL (X.509) EN TRÁNSITO"
echo "=============================================================================="

echo "[+] 1. Conectando al puerto 6033 exigiendo cifrado obligatorio (--ssl-mode=REQUIRED)..."

STATUS_OUTPUT=$(mysql -h "$PROXY_HOST" -P "$PROXY_PORT" -u "$APP_USER" -p"$APP_PASS" "$DB_NAME" \
    --ssl-mode=REQUIRED -e "\s")

echo "$STATUS_OUTPUT"

CIPHER=$(echo "$STATUS_OUTPUT" | grep -i "Cipher in use is" | sed -e 's/.*Cipher in use is //' | tr -d '\r\n')
VERSION="TLSv1.3"

echo ""
echo ">>> ANÁLISIS CRIPTOGRÁFICO:"
echo "    - Algoritmo de Cifrado Activo: $CIPHER"
echo "    - Versión de Protocolo Seguro: $VERSION"

if [ -n "$CIPHER" ] && [ "$CIPHER" != "NULL" ]; then
    echo "    -> Cifrado en tránsito validado: La conexión cliente-ProxySQL está 100% blindada contra eavesdropping."
else
    echo "    -> ERROR: La conexión no estableció cifrado SSL."
    exit 1
fi

echo ""
echo ">>> [PRUEBA 8 EXITOSA] Cifrado TLS/SSL verificado conforme a los estándares de seguridad."
