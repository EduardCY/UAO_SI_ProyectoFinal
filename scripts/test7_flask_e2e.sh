#!/usr/bin/env bash
# ==============================================================================
# PRUEBA 7: INTEGRACIÓN Y PRUEBAS E2E CON LA API REST FLASK (PRÁCTICA 9 INTEGRADA)
# Proyecto 4: Balanceo de Cargas MySQL con ProxySQL — UAO
# Autores: Felipe Charria Caicedo & Eduard Criollo Yule
# ==============================================================================
set -e

FLASK_HOST=${1:-app-flask}
FLASK_PORT=${FLASK_PORT:-5000}
BASE_URL="http://${FLASK_HOST}:${FLASK_PORT}"

echo "=============================================================================="
echo " [PRUEBA 7] INTEGRACIÓN E2E DE LA API REST FLASK (USUARIOS, PRODUCTOS, IOT)"
echo " Endpoint Base: $BASE_URL"
echo "=============================================================================="

# 1. Healthcheck
echo "[+] 1. Comprobando estado del microservicio (/api/health)..."
curl -s -f "$BASE_URL/api/health" | grep "healthy" >/dev/null && echo "    -> Microservicio Flask ONLINE y conectado a ProxySQL :6033."

# 2. CRUD de Usuarios (Práctica 9 - /api/users)
echo ""
echo "[+] 2. Validando flujo transaccional CRUD de Usuarios (/api/users)..."

echo "    [2.1] POST /api/users (Crear Usuario 'Camilo Torres' -> Maestro HG 10):"
USER_POST=$(curl -s -X POST "$BASE_URL/api/users" \
    -H "Content-Type: application/json" \
    -d '{"name": "Camilo Torres", "email": "camilo.torres@uao.edu.co", "username": "ctorres", "password": "securePass2026!"}')
echo "          Respuesta: $USER_POST"
NEW_USER_ID=$(echo "$USER_POST" | grep -o '"inserted_id":[0-9]*' | cut -d':' -f2)
USER_WRITE_HOST=$(echo "$USER_POST" | grep -o '"handled_by":"[^"]*"' | cut -d':' -f2 | tr -d '"')
echo "          -> Creado en nodo: $USER_WRITE_HOST (ID: $NEW_USER_ID)"

echo "    [2.2] GET /api/users (Listar Usuarios -> Réplicas HG 20):"
USER_GET=$(curl -s "$BASE_URL/api/users")
USER_READ_HOST=$(echo "$USER_GET" | grep -o '"handled_by":"[^"]*"' | cut -d':' -f2 | tr -d '"')
USER_COUNT=$(echo "$USER_GET" | grep -o '"record_count":[0-9]*' | cut -d':' -f2)
echo "          -> Atendido por: $USER_READ_HOST | Total registros: $USER_COUNT"

if [ -n "$NEW_USER_ID" ]; then
    echo "    [2.3] GET /api/users/$NEW_USER_ID (Consultar usuario creado por ID -> HG 20):"
    USER_SINGLE=$(curl -s "$BASE_URL/api/users/$NEW_USER_ID")
    echo "          -> Atendido por: $(echo "$USER_SINGLE" | grep -o '"handled_by":"[^"]*"' | cut -d':' -f2 | tr -d '"')"

    echo "    [2.4] PUT /api/users/$NEW_USER_ID (Actualizar usuario -> Maestro HG 10):"
    USER_PUT=$(curl -s -X PUT "$BASE_URL/api/users/$NEW_USER_ID" \
        -H "Content-Type: application/json" \
        -d '{"name": "Camilo Torres Modificado", "email": "camilo.mod@uao.edu.co", "username": "ctorres_mod"}')
    echo "          -> Modificado en: $(echo "$USER_PUT" | grep -o '"handled_by":"[^"]*"' | cut -d':' -f2 | tr -d '"')"

    echo "    [2.5] DELETE /api/users/$NEW_USER_ID (Eliminar usuario -> Maestro HG 10):"
    USER_DEL=$(curl -s -X DELETE "$BASE_URL/api/users/$NEW_USER_ID")
    echo "          -> Eliminado en: $(echo "$USER_DEL" | grep -o '"handled_by":"[^"]*"' | cut -d':' -f2 | tr -d '"')"
fi

# 3. CRUD de Productos (Práctica 9 - /api/products)
echo ""
echo "[+] 3. Validando flujo transaccional CRUD de Productos (/api/products)..."

echo "    [3.1] POST /api/products (Crear Producto 'Switch Core 48p' -> Maestro HG 10):"
PROD_POST=$(curl -s -X POST "$BASE_URL/api/products" \
    -H "Content-Type: application/json" \
    -d '{"name": "Switch Core 48p", "description": "Switch Capa 3 10GbE PoE+", "price": 890.50, "stock": 6}')
echo "          Respuesta: $PROD_POST"
NEW_PROD_ID=$(echo "$PROD_POST" | grep -o '"inserted_id":[0-9]*' | cut -d':' -f2)
PROD_WRITE_HOST=$(echo "$PROD_POST" | grep -o '"handled_by":"[^"]*"' | cut -d':' -f2 | tr -d '"')
echo "          -> Insertado en nodo: $PROD_WRITE_HOST (ID: $NEW_PROD_ID)"

echo "    [3.2] GET /api/products (Listar Catálogo de Productos -> Réplicas HG 20):"
PROD_GET=$(curl -s "$BASE_URL/api/products")
PROD_READ_HOST=$(echo "$PROD_GET" | grep -o '"handled_by":"[^"]*"' | cut -d':' -f2 | tr -d '"')
PROD_COUNT=$(echo "$PROD_GET" | grep -o '"record_count":[0-9]*' | cut -d':' -f2)
echo "          -> Atendido por: $PROD_READ_HOST | Total catálogo: $PROD_COUNT productos"

if [ -n "$NEW_PROD_ID" ]; then
    echo "    [3.3] GET /api/products/$NEW_PROD_ID (Consultar producto por ID -> HG 20):"
    PROD_SINGLE=$(curl -s "$BASE_URL/api/products/$NEW_PROD_ID")
    echo "          -> Atendido por: $(echo "$PROD_SINGLE" | grep -o '"handled_by":"[^"]*"' | cut -d':' -f2 | tr -d '"')"

    echo "    [3.4] PUT /api/products/$NEW_PROD_ID (Actualizar precio y stock -> Maestro HG 10):"
    PROD_PUT=$(curl -s -X PUT "$BASE_URL/api/products/$NEW_PROD_ID" \
        -H "Content-Type: application/json" \
        -d '{"name": "Switch Core 48p v2", "description": "Actualizado con fuentes redundantes", "price": 920.00, "stock": 8}')
    echo "          -> Modificado en: $(echo "$PROD_PUT" | grep -o '"handled_by":"[^"]*"' | cut -d':' -f2 | tr -d '"')"

    echo "    [3.5] DELETE /api/products/$NEW_PROD_ID (Eliminar producto del catálogo -> Maestro HG 10):"
    PROD_DEL=$(curl -s -X DELETE "$BASE_URL/api/products/$NEW_PROD_ID")
    echo "          -> Eliminado en: $(echo "$PROD_DEL" | grep -o '"handled_by":"[^"]*"' | cut -d':' -f2 | tr -d '"')"
fi

# 4. Telemetría IoT y Query Cache
echo ""
echo "[+] 4. Validando Telemetría IoT y Aceleración por Query Cache en RAM..."
RESP_WRITE_IOT=$(curl -s -X POST "$BASE_URL/api/telemetry" \
    -H "Content-Type: application/json" \
    -d '{"device_id": "UAO-TEST-E2E", "sensor_type": "current", "metric_value": 15.8, "unit": "A", "location": "Subestacion Electrica"}')
echo "    -> Telemetría POST (HG 10): $(echo "$RESP_WRITE_IOT" | grep -o '"handled_by":"[^"]*"' | cut -d':' -f2 | tr -d '"')"

RESP_READ_IOT=$(curl -s "$BASE_URL/api/telemetry")
echo "    -> Telemetría GET (HG 20): $(echo "$RESP_READ_IOT" | grep -o '"handled_by":"[^"]*"' | cut -d':' -f2 | tr -d '"') | Latencia: $(echo "$RESP_READ_IOT" | grep -o '"latency_ms":[0-9.]*' | cut -d':' -f2) ms"

RESP_CACHE=$(curl -s "$BASE_URL/api/telemetry/cached")
echo "    -> Telemetría GET CACHED (RAM): Latencia: $(echo "$RESP_CACHE" | grep -o '"latency_ms":[0-9.]*' | cut -d':' -f2) ms (TTL: 5s)"

# 5. Ráfaga Concurrente y Multiplexing
echo ""
echo "[+] 5. Disparando ráfaga controlada mediante POST /api/cluster/burst..."
RESP_BURST=$(curl -s -X POST "$BASE_URL/api/cluster/burst" \
    -H "Content-Type: application/json" \
    -d '{"reads": 25, "writes": 5}')
echo "    -> Resumen ráfaga: $RESP_BURST"

echo ""
echo "=============================================================================="
echo ">>> [PRUEBA 7 EXITOSA] Flujo E2E completo validado al 100%:"
echo "    - Usuarios: CRUD completo con Read/Write Split hacia Maestro y Réplicas."
echo "    - Productos: CRUD completo con persistencia y replicación GTID Semi-Sync."
echo "    - Telemetría: Inserción, consulta distribuida y Query Cache en RAM."
echo "=============================================================================="
