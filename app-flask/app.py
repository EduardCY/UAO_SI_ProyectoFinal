#!/usr/bin/env python3
"""
Microservicio API REST + Dashboard en Tiempo Real (Práctica 9 + Telemetría IoT Integrada).
Proyecto 4: Balanceo de Cargas MySQL con ProxySQL 2.x
Universidad Autónoma de Occidente — Servicios Telemáticos (2026-02)
Autores: Eduard Criollo Yule y Felipe Charria Caicedo
"""

from concurrent.futures import ThreadPoolExecutor, as_completed
import os
import time
import pymysql
from pymysql.constants import CLIENT
from flask import Flask, jsonify, render_template, request

app = Flask(__name__)

# Configuración desde variables de entorno
PROXY_HOST = os.getenv("PROXYSQL_HOST", "proxysql")
PROXY_DATA_PORT = int(os.getenv("PROXYSQL_DATA_PORT", "6033"))
PROXY_ADMIN_PORT = int(os.getenv("PROXYSQL_ADMIN_PORT", "6032"))
DB_USER = os.getenv("MYSQL_APP_USER", "cluster_app")
DB_PASS = os.getenv("MYSQL_APP_PASSWORD", "AppPassword2026!")
DB_NAME = os.getenv("MYSQL_DATABASE", "telematicos_db")
ADMIN_USER = os.getenv("PROXYSQL_ADMIN_USER", "radmin")
ADMIN_PASS = os.getenv("PROXYSQL_ADMIN_PASSWORD", "radmin")


def get_data_connection():
    """
    Establece conexión cliente MySQL hacia ProxySQL en el puerto de tráfico L7 (6033).
    Habilita soporte TLS/SSL para validar cifrado en tránsito.
    """
    return pymysql.connect(
        host=PROXY_HOST,
        port=PROXY_DATA_PORT,
        user=DB_USER,
        password=DB_PASS,
        database=DB_NAME,
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True,
        connect_timeout=3,
        client_flag=CLIENT.SSL
    )


def get_admin_connection():
    """
    Establece conexión administrativa hacia la base de datos interna SQLite de ProxySQL (6032).
    Permite introspección de hostgroups, estadísticas y digest en tiempo real.
    """
    return pymysql.connect(
        host=PROXY_HOST,
        port=PROXY_ADMIN_PORT,
        user=ADMIN_USER,
        password=ADMIN_PASS,
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True,
        connect_timeout=3
    )


def get_request_data():
    """
    Extrae los datos de la petición HTTP con resiliencia multi-formato:
    Soporta application/json nativo, JSON forzado y application/x-www-form-urlencoded.
    """
    if request.is_json:
        data = request.get_json(silent=True)
        if data is not None:
            return data
    try:
        data = request.get_json(force=True, silent=True)
        if data is not None:
            return data
    except Exception:
        pass
    if request.form:
        return request.form.to_dict()
    return {}


# =============================================================================
# RUTAS DE VISTAS WEB
# =============================================================================

@app.route("/")
def index():
    """Renderiza el Dashboard Web Windows 98 / SCADA Retro para la sustentación y gestión interactiva."""
    return render_template("index.html")


@app.route("/api/health")
def health():
    """Endpoint de comprobación de salud del microservicio."""
    try:
        conn = get_data_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT 1 AS alive, @@hostname AS host, @@server_id AS server_id;")
            res = cur.fetchone()
        conn.close()
        return jsonify({"status": "healthy", "database": res})
    except Exception as e:
        return jsonify({"status": "unhealthy", "error": str(e)}), 500


# =============================================================================
# 1. API REST CRUD DE USUARIOS (Práctica 9 - /api/users)
# =============================================================================

@app.route("/api/users", methods=["GET"])
def get_users():
    """
    Listar usuarios de MySQL a través de ProxySQL (Read Split -> HG 20).
    """
    start_time = time.perf_counter()
    try:
        conn = get_data_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT @@hostname AS responding_host, @@server_id AS server_id;")
            node_info = cur.fetchone()
            cur.execute("SELECT id, name, email, username, created_at FROM users ORDER BY id ASC;")
            users = cur.fetchall()
        conn.close()
        duration_ms = (time.perf_counter() - start_time) * 1000.0

        for u in users:
            if u.get("created_at"):
                u["created_at"] = str(u["created_at"])

        return jsonify({
            "success": True,
            "operation": "GET /api/users (Read Split)",
            "hostgroup_target": "HG 20 (Replicas)",
            "handled_by": node_info.get("responding_host"),
            "server_id": node_info.get("server_id"),
            "latency_ms": round(duration_ms, 3),
            "record_count": len(users),
            "data": users
        }), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/api/users/<int:user_id>", methods=["GET"])
def get_user(user_id: int):
    """
    Consultar un usuario por ID (Read Split -> HG 20).
    """
    start_time = time.perf_counter()
    try:
        conn = get_data_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT @@hostname AS responding_host, @@server_id AS server_id;")
            node_info = cur.fetchone()
            cur.execute("SELECT id, name, email, username, created_at FROM users WHERE id = %s;", (user_id,))
            user = cur.fetchone()
        conn.close()
        duration_ms = (time.perf_counter() - start_time) * 1000.0

        if not user:
            return jsonify({
                "success": False,
                "error": "Not Found",
                "message": f"Usuario con ID {user_id} no existe."
            }), 404

        if user.get("created_at"):
            user["created_at"] = str(user["created_at"])

        return jsonify({
            "success": True,
            "operation": f"GET /api/users/{user_id} (Read Split)",
            "hostgroup_target": "HG 20 (Replicas)",
            "handled_by": node_info.get("responding_host"),
            "server_id": node_info.get("server_id"),
            "latency_ms": round(duration_ms, 3),
            "data": user
        }), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/api/users", methods=["POST"])
def create_user():
    """
    Crear un nuevo usuario en MySQL (Write Split -> HG 10 Maestro).
    """
    payload = get_request_data()
    name = str(payload.get("name", "")).strip()
    email = str(payload.get("email", "")).strip()
    username = str(payload.get("username", "")).strip()
    password = str(payload.get("password", "123456"))

    if not name or not email or not username:
        return jsonify({
            "success": False,
            "error": "Bad Request",
            "message": "Se requieren 'name', 'email' y 'username' no vacíos."
        }), 400

    start_time = time.perf_counter()
    try:
        conn = get_data_connection()
        with conn.cursor() as cur:
            cur.execute("START TRANSACTION;")
            cur.execute(
                "INSERT INTO users (name, email, username, password) VALUES (%s, %s, %s, %s);",
                (name, email, username, password)
            )
            inserted_id = cur.lastrowid
            cur.execute("SELECT @@hostname AS responding_host, @@server_id AS server_id;")
            node_info = cur.fetchone()
            cur.execute("COMMIT;")
        conn.close()
        duration_ms = (time.perf_counter() - start_time) * 1000.0

        return jsonify({
            "success": True,
            "operation": "POST /api/users (Write Split)",
            "hostgroup_target": "HG 10 (Master)",
            "handled_by": node_info.get("responding_host"),
            "server_id": node_info.get("server_id"),
            "inserted_id": inserted_id,
            "latency_ms": round(duration_ms, 3),
            "message": f"Usuario '{name}' creado exitosamente en el Maestro."
        }), 201
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/api/users/<int:user_id>", methods=["PUT"])
def update_user(user_id: int):
    """
    Actualizar usuario existente (Write Split -> HG 10 Maestro).
    """
    payload = get_request_data()
    start_time = time.perf_counter()
    try:
        conn = get_data_connection()
        with conn.cursor() as cur:
            cur.execute("START TRANSACTION;")
            cur.execute("SELECT id, name, email, username FROM users WHERE id = %s FOR UPDATE;", (user_id,))
            current = cur.fetchone()
            if not current:
                cur.execute("ROLLBACK;")
                conn.close()
                return jsonify({"success": False, "error": "Not Found"}), 404

            name = str(payload.get("name", current["name"])).strip()
            email = str(payload.get("email", current["email"])).strip()
            username = str(payload.get("username", current["username"])).strip()

            cur.execute(
                "UPDATE users SET name = %s, email = %s, username = %s WHERE id = %s;",
                (name, email, username, user_id)
            )
            cur.execute("SELECT @@hostname AS responding_host, @@server_id AS server_id;")
            node_info = cur.fetchone()
            cur.execute("COMMIT;")
        conn.close()
        duration_ms = (time.perf_counter() - start_time) * 1000.0

        return jsonify({
            "success": True,
            "operation": f"PUT /api/users/{user_id} (Write Split)",
            "hostgroup_target": "HG 10 (Master)",
            "handled_by": node_info.get("responding_host"),
            "server_id": node_info.get("server_id"),
            "latency_ms": round(duration_ms, 3),
            "message": f"Usuario ID {user_id} actualizado en el Maestro."
        }), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/api/users/<int:user_id>", methods=["DELETE"])
def delete_user(user_id: int):
    """
    Eliminar usuario existente (Write Split -> HG 10 Maestro).
    """
    start_time = time.perf_counter()
    try:
        conn = get_data_connection()
        with conn.cursor() as cur:
            cur.execute("START TRANSACTION;")
            cur.execute("SELECT id FROM users WHERE id = %s FOR UPDATE;", (user_id,))
            if not cur.fetchone():
                cur.execute("ROLLBACK;")
                conn.close()
                return jsonify({"success": False, "error": "Not Found"}), 404

            cur.execute("DELETE FROM users WHERE id = %s;", (user_id,))
            cur.execute("SELECT @@hostname AS responding_host, @@server_id AS server_id;")
            node_info = cur.fetchone()
            cur.execute("COMMIT;")
        conn.close()
        duration_ms = (time.perf_counter() - start_time) * 1000.0

        return jsonify({
            "success": True,
            "operation": f"DELETE /api/users/{user_id} (Write Split)",
            "hostgroup_target": "HG 10 (Master)",
            "handled_by": node_info.get("responding_host"),
            "server_id": node_info.get("server_id"),
            "latency_ms": round(duration_ms, 3),
            "message": f"Usuario ID {user_id} eliminado físicamente en el Maestro."
        }), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


# =============================================================================
# 2. API REST CRUD DE PRODUCTOS (Práctica 9 - /api/products)
# =============================================================================

@app.route("/api/products", methods=["GET"])
def get_products():
    """
    Listar catálogo completo de productos (Read Split -> HG 20).
    """
    start_time = time.perf_counter()
    try:
        conn = get_data_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT @@hostname AS responding_host, @@server_id AS server_id;")
            node_info = cur.fetchone()
            cur.execute("SELECT id, name, description, price, stock, created_at FROM products ORDER BY id ASC;")
            products = cur.fetchall()
        conn.close()
        duration_ms = (time.perf_counter() - start_time) * 1000.0

        for p in products:
            p["price"] = float(p["price"]) if p.get("price") is not None else 0.0
            if p.get("created_at"):
                p["created_at"] = str(p["created_at"])

        return jsonify({
            "success": True,
            "operation": "GET /api/products (Read Split)",
            "hostgroup_target": "HG 20 (Replicas)",
            "handled_by": node_info.get("responding_host"),
            "server_id": node_info.get("server_id"),
            "latency_ms": round(duration_ms, 3),
            "record_count": len(products),
            "data": products
        }), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/api/products/<int:prod_id>", methods=["GET"])
def get_product(prod_id: int):
    """
    Consultar producto específico por ID (Read Split -> HG 20).
    """
    start_time = time.perf_counter()
    try:
        conn = get_data_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT @@hostname AS responding_host, @@server_id AS server_id;")
            node_info = cur.fetchone()
            cur.execute("SELECT id, name, description, price, stock, created_at FROM products WHERE id = %s;", (prod_id,))
            prod = cur.fetchone()
        conn.close()
        duration_ms = (time.perf_counter() - start_time) * 1000.0

        if not prod:
            return jsonify({
                "success": False,
                "error": "Not Found",
                "message": f"Producto con ID {prod_id} no existe."
            }), 404

        prod["price"] = float(prod["price"]) if prod.get("price") is not None else 0.0
        if prod.get("created_at"):
            prod["created_at"] = str(prod["created_at"])

        return jsonify({
            "success": True,
            "operation": f"GET /api/products/{prod_id} (Read Split)",
            "hostgroup_target": "HG 20 (Replicas)",
            "handled_by": node_info.get("responding_host"),
            "server_id": node_info.get("server_id"),
            "latency_ms": round(duration_ms, 3),
            "data": prod
        }), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/api/products", methods=["POST"])
def create_product():
    """
    Registrar un nuevo producto en el catálogo (Write Split -> HG 10 Maestro).
    """
    payload = get_request_data()
    name = str(payload.get("name", "")).strip()
    description = str(payload.get("description", "")).strip()
    try:
        price = float(payload.get("price", 0.0))
        stock = int(payload.get("stock", 0))
    except (ValueError, TypeError):
        return jsonify({"success": False, "error": "Bad Request", "message": "'price' y 'stock' deben ser numéricos."}), 400

    if not name:
        return jsonify({"success": False, "error": "Bad Request", "message": "El campo 'name' es obligatorio."}), 400

    start_time = time.perf_counter()
    try:
        conn = get_data_connection()
        with conn.cursor() as cur:
            cur.execute("START TRANSACTION;")
            cur.execute(
                "INSERT INTO products (name, description, price, stock) VALUES (%s, %s, %s, %s);",
                (name, description, price, stock)
            )
            inserted_id = cur.lastrowid
            cur.execute("SELECT @@hostname AS responding_host, @@server_id AS server_id;")
            node_info = cur.fetchone()
            cur.execute("COMMIT;")
        conn.close()
        duration_ms = (time.perf_counter() - start_time) * 1000.0

        return jsonify({
            "success": True,
            "operation": "POST /api/products (Write Split)",
            "hostgroup_target": "HG 10 (Master)",
            "handled_by": node_info.get("responding_host"),
            "server_id": node_info.get("server_id"),
            "inserted_id": inserted_id,
            "latency_ms": round(duration_ms, 3),
            "message": f"Producto '{name}' insertado exitosamente en el Maestro."
        }), 201
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/api/products/<int:prod_id>", methods=["PUT"])
def update_product(prod_id: int):
    """
    Actualizar producto existente (Write Split -> HG 10 Maestro).
    """
    payload = get_request_data()
    start_time = time.perf_counter()
    try:
        conn = get_data_connection()
        with conn.cursor() as cur:
            cur.execute("START TRANSACTION;")
            cur.execute("SELECT id, name, description, price, stock FROM products WHERE id = %s FOR UPDATE;", (prod_id,))
            current = cur.fetchone()
            if not current:
                cur.execute("ROLLBACK;")
                conn.close()
                return jsonify({"success": False, "error": "Not Found"}), 404

            name = str(payload.get("name", current["name"])).strip()
            description = str(payload.get("description", current["description"])).strip()
            price = float(payload.get("price", current["price"]))
            stock = int(payload.get("stock", current["stock"]))

            cur.execute(
                "UPDATE products SET name = %s, description = %s, price = %s, stock = %s WHERE id = %s;",
                (name, description, price, stock, prod_id)
            )
            cur.execute("SELECT @@hostname AS responding_host, @@server_id AS server_id;")
            node_info = cur.fetchone()
            cur.execute("COMMIT;")
        conn.close()
        duration_ms = (time.perf_counter() - start_time) * 1000.0

        return jsonify({
            "success": True,
            "operation": f"PUT /api/products/{prod_id} (Write Split)",
            "hostgroup_target": "HG 10 (Master)",
            "handled_by": node_info.get("responding_host"),
            "server_id": node_info.get("server_id"),
            "latency_ms": round(duration_ms, 3),
            "message": f"Producto ID {prod_id} actualizado en el Maestro."
        }), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/api/products/<int:prod_id>", methods=["DELETE"])
def delete_product(prod_id: int):
    """
    Eliminar producto del catálogo (Write Split -> HG 10 Maestro).
    """
    start_time = time.perf_counter()
    try:
        conn = get_data_connection()
        with conn.cursor() as cur:
            cur.execute("START TRANSACTION;")
            cur.execute("SELECT id FROM products WHERE id = %s FOR UPDATE;", (prod_id,))
            if not cur.fetchone():
                cur.execute("ROLLBACK;")
                conn.close()
                return jsonify({"success": False, "error": "Not Found"}), 404

            cur.execute("DELETE FROM products WHERE id = %s;", (prod_id,))
            cur.execute("SELECT @@hostname AS responding_host, @@server_id AS server_id;")
            node_info = cur.fetchone()
            cur.execute("COMMIT;")
        conn.close()
        duration_ms = (time.perf_counter() - start_time) * 1000.0

        return jsonify({
            "success": True,
            "operation": f"DELETE /api/products/{prod_id} (Write Split)",
            "hostgroup_target": "HG 10 (Master)",
            "handled_by": node_info.get("responding_host"),
            "server_id": node_info.get("server_id"),
            "latency_ms": round(duration_ms, 3),
            "message": f"Producto ID {prod_id} eliminado físicamente en el Maestro."
        }), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


# =============================================================================
# 3. API DE TELEMETRÍA IOT Y QUERY CACHE
# =============================================================================

@app.route("/api/telemetry", methods=["GET"])
def get_telemetry():
    """
    Ejecuta consulta SELECT a través de ProxySQL (Read Split -> HG 20).
    """
    start_time = time.perf_counter()
    try:
        conn = get_data_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT @@hostname AS responding_host, @@server_id AS server_id;")
            node_info = cur.fetchone()
            cur.execute(
                "SELECT id, device_id, sensor_type, metric_value, unit, campus_location, recorded_at "
                "FROM iot_telemetry ORDER BY id DESC LIMIT 10;"
            )
            records = cur.fetchall()
        conn.close()
        duration_ms = (time.perf_counter() - start_time) * 1000.0

        for r in records:
            r["metric_value"] = float(r["metric_value"]) if r.get("metric_value") is not None else 0.0
            if r.get("recorded_at"):
                r["recorded_at"] = str(r["recorded_at"])

        return jsonify({
            "success": True,
            "operation": "GET /api/telemetry (Read Split)",
            "hostgroup_target": "HG 20 (Replicas)",
            "handled_by": node_info.get("responding_host"),
            "server_id": node_info.get("server_id"),
            "latency_ms": round(duration_ms, 3),
            "record_count": len(records),
            "data": records
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/api/telemetry/cached", methods=["GET"])
def get_telemetry_cached():
    """
    Ejecuta consulta con hint de Query Cache (rule_id=30).
    Demuestra aceleración en memoria RAM y respuesta sub-milisegundo.
    """
    start_time = time.perf_counter()
    try:
        conn = get_data_connection()
        with conn.cursor() as cur:
            cur.execute(
                "SELECT /*+ CACHE */ id, device_id, sensor_type, metric_value, unit, campus_location "
                "FROM iot_telemetry ORDER BY id ASC LIMIT 5;"
            )
            records = cur.fetchall()
        conn.close()
        duration_ms = (time.perf_counter() - start_time) * 1000.0

        for r in records:
            r["metric_value"] = float(r["metric_value"]) if r.get("metric_value") is not None else 0.0

        return jsonify({
            "success": True,
            "operation": "SELECT with /*+ CACHE */ Hint",
            "cached": True,
            "latency_ms": round(duration_ms, 3),
            "cache_ttl_sec": 5,
            "record_count": len(records),
            "data": records
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/api/telemetry", methods=["POST"])
def post_telemetry():
    """
    Ejecuta sentencia INSERT a través de ProxySQL (Write Split -> HG 10 Maestro).
    """
    payload = get_request_data()
    device_id = payload.get("device_id", f"UAO-DEV-{int(time.time()) % 1000}")
    sensor_type = payload.get("sensor_type", "temperature")
    metric_value = float(payload.get("metric_value", 24.5))
    unit = payload.get("unit", "C")
    location = payload.get("location", "Edificio Bienestar Universitario")

    start_time = time.perf_counter()
    try:
        conn = get_data_connection()
        with conn.cursor() as cur:
            cur.execute("START TRANSACTION;")
            cur.execute(
                "INSERT INTO iot_telemetry (device_id, sensor_type, metric_value, unit, campus_location) "
                "VALUES (%s, %s, %s, %s, %s);",
                (device_id, sensor_type, metric_value, unit, location)
            )
            inserted_id = cur.lastrowid
            cur.execute("SELECT @@hostname AS responding_host, @@server_id AS server_id;")
            node_info = cur.fetchone()
            cur.execute("COMMIT;")
        conn.close()
        duration_ms = (time.perf_counter() - start_time) * 1000.0

        return jsonify({
            "success": True,
            "operation": "POST /api/telemetry (Write Split)",
            "hostgroup_target": "HG 10 (Master)",
            "handled_by": node_info.get("responding_host"),
            "server_id": node_info.get("server_id"),
            "inserted_id": inserted_id,
            "latency_ms": round(duration_ms, 3),
            "message": "Registro de telemetría almacenado exitosamente en el Maestro."
        }), 201
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


# =============================================================================
# 4. INTROSPECCIÓN PROXYSQL Y RÁFAGAS CONCURRENTES
# =============================================================================

@app.route("/api/cluster/burst", methods=["POST"])
def trigger_burst():
    """
    Dispara una ráfaga controlada de N peticiones para demostrar en vivo
    la distribución de carga y el multiplexing de conexiones.
    """
    payload = get_request_data()
    reads = int(payload.get("reads", 30))
    writes = int(payload.get("writes", 5))
    workers = min(max(4, (reads + writes) // 4), 16)

    stats = {
        "total_requests": reads + writes,
        "writes_executed": 0,
        "reads_executed": 0,
        "hosts_distribution": {},
        "errors": []
    }

    def _run_write(idx):
        conn = get_data_connection()
        try:
            with conn.cursor() as cur:
                cur.execute("START TRANSACTION;")
                cur.execute(
                    "INSERT INTO iot_telemetry (device_id, sensor_type, metric_value, unit, campus_location) "
                    "VALUES (%s, %s, %s, %s, %s);",
                    (f"BURST-WRITER-{idx}", "burst_test", 100.0 + idx, "cnt", "Lab Telecomunicaciones")
                )
                cur.execute("SELECT @@hostname AS host;")
                host = cur.fetchone()["host"]
                cur.execute("COMMIT;")
            return ("write", host, None)
        except Exception as e:
            return ("write", None, f"Write {idx} error: {str(e)}")
        finally:
            conn.close()

    def _run_read(_idx):
        conn = get_data_connection()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT @@hostname AS host;")
                host = cur.fetchone()["host"]
            return ("read", host, None)
        except Exception as e:
            return ("read", None, f"Read {_idx} error: {str(e)}")
        finally:
            conn.close()

    start_time = time.perf_counter()
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(_run_write, i) for i in range(writes)] + [
            pool.submit(_run_read, i) for i in range(reads)
        ]
        for fut in as_completed(futures):
            kind, host, err = fut.result()
            if err:
                stats["errors"].append(err)
            elif host:
                stats["hosts_distribution"][host] = stats["hosts_distribution"].get(host, 0) + 1
                if kind == "write":
                    stats["writes_executed"] += 1
                else:
                    stats["reads_executed"] += 1

    stats["total_duration_ms"] = round((time.perf_counter() - start_time) * 1000.0, 2)
    return jsonify(stats)


@app.route("/api/cluster/stats", methods=["GET"])
def get_cluster_stats():
    """
    Extrae telemetría interna en vivo desde ProxySQL (puerto 6032).
    Proporciona estado de servidores, connection pool y query digest.
    """
    try:
        admin_conn = get_admin_connection()
        with admin_conn.cursor() as cur:
            cur.execute(
                "SELECT hostgroup AS hostgroup_id, srv_host AS hostname, srv_port AS port, status, "
                "ConnUsed, ConnFree, ConnOK, ConnERR AS ConnErrors, Queries, Latency_us "
                "FROM stats_mysql_connection_pool;"
            )
            pool = cur.fetchall()

            cur.execute(
                "SELECT rule_id, hits FROM stats_mysql_query_rules WHERE hits > 0 ORDER BY rule_id;"
            )
            rules_stats = cur.fetchall()

            cur.execute(
                "SELECT hostgroup, digest, digest_text, count_star, sum_time, min_time, max_time "
                "FROM stats_mysql_query_digest ORDER BY count_star DESC LIMIT 6;"
            )
            digest = cur.fetchall()

        admin_conn.close()
        return jsonify({
            "success": True,
            "connection_pool": pool,
            "rules_hits": rules_stats,
            "query_digest": digest
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
