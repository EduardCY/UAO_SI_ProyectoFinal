-- ==============================================================================
-- PROYECTO 4: INICIALIZACIÓN DE NODO MAESTRO (MySQL 8.0)
-- Servicios Telemáticos — Universidad Autónoma de Occidente
-- ==============================================================================

SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;

-- 1. Bases de Datos
CREATE DATABASE IF NOT EXISTS telematicos_db;
CREATE DATABASE IF NOT EXISTS sbtest;

-- 2. Usuarios del Clúster y Privilegios Mínimos
-- Usuario para Replicación GTID
CREATE USER IF NOT EXISTS 'repl_user'@'%' IDENTIFIED WITH mysql_native_password BY 'ReplPassword2026!';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'repl_user'@'%';

-- Usuario para Monitoreo de Estado por ProxySQL (Healthchecks, Lag, Read_Only)
CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED WITH mysql_native_password BY 'MonitorPassword2026!';
GRANT USAGE, REPLICATION CLIENT, PROCESS ON *.* TO 'monitor'@'%';

-- Usuario de Aplicación (Sysbench, Flask API, Telemetría)
CREATE USER IF NOT EXISTS 'cluster_app'@'%' IDENTIFIED WITH mysql_native_password BY 'AppPassword2026!';
GRANT ALL PRIVILEGES ON telematicos_db.* TO 'cluster_app'@'%';
GRANT ALL PRIVILEGES ON sbtest.* TO 'cluster_app'@'%';

-- 3. Plugins de Replicación Semi-Síncrona (MySQL 8.0)
-- Configuración defensiva con timeout de 1000ms para evitar bloqueos si caen los esclavos
INSTALL PLUGIN rpl_semi_sync_master SONAME 'semisync_master.so';
SET GLOBAL rpl_semi_sync_master_enabled = 1;
SET GLOBAL rpl_semi_sync_master_timeout = 1000;

-- 4. Esquema de Telemetría IoT, Usuarios y Catálogo de Productos (Práctica 9 Integrada)
USE telematicos_db;

CREATE TABLE IF NOT EXISTS iot_telemetry (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    device_id VARCHAR(64) NOT NULL,
    sensor_type VARCHAR(32) NOT NULL,
    metric_value DECIMAL(10, 4) NOT NULL,
    unit VARCHAR(16) NOT NULL,
    campus_location VARCHAR(128) NOT NULL,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_device (device_id),
    INDEX idx_recorded (recorded_at)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS routing_audit (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    operation VARCHAR(16) NOT NULL,
    client_ip VARCHAR(64),
    payload TEXT,
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Tablas de la Aplicación Web Real (Práctica 9 - Gestión de Usuarios y Productos)
CREATE TABLE IF NOT EXISTS users (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    username VARCHAR(255) NOT NULL,
    password VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS products (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description VARCHAR(255) DEFAULT '',
    price DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    stock INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Datos Semilla de Telemetría Campus UAO
INSERT INTO iot_telemetry (device_id, sensor_type, metric_value, unit, campus_location) VALUES
('UAO-IOT-ED3-01', 'temperature', 23.4500, 'C', 'Edificio Aulas 3 - Piso 2 - Lab Redes'),
('UAO-IOT-ED3-02', 'humidity', 58.2000, '%', 'Edificio Aulas 3 - Piso 2 - Lab Redes'),
('UAO-IOT-ED4-01', 'power_consumption', 142.8000, 'W', 'Edificio Aulas 4 - Centro de Cómputo'),
('UAO-IOT-SOLAR-01', 'solar_irradiance', 895.5000, 'W/m2', 'Edificio Central - Techo Solar'),
('UAO-IOT-AUD-01', 'co2_level', 412.0000, 'ppm', 'Auditorio Yquinde');

-- Datos Semilla de Usuarios (Práctica 9)
INSERT INTO users (id, name, email, username, password) VALUES
(1, 'Eduard Criollo', 'eduard.criollo@uao.edu.co', 'ecriollo', 'Pass2026!'),
(2, 'Felipe Charria', 'felipe.charria@uao.edu.co', 'fcharria', 'Pass2026!'),
(3, 'Oscar Mondragon', 'omondragon@uao.edu.co', 'omondragon', 'Prof2026!')
ON DUPLICATE KEY UPDATE name=VALUES(name), email=VALUES(email);

-- Datos Semilla de Productos (Práctica 9)
INSERT INTO products (id, name, description, price, stock) VALUES
(1, 'Laptop Pro 15', 'Portátil de alto rendimiento 16GB RAM 512GB NVMe', 1250.00, 15),
(2, 'Monitor UltraWide 34', 'Monitor curvo WQHD IPS 144Hz para desarrollo', 480.50, 8),
(3, 'Teclado Mecánico RGB', 'Switches táctiles silenciosos formato TKL', 95.00, 25),
(4, 'Mouse Inalámbrico Pro', 'Sensor óptico 25K DPI baja latencia', 79.99, 30),
(5, 'Access Point WiFi 6', 'Dispositivo telemático doble banda Gigabit PoE', 185.00, 12)
ON DUPLICATE KEY UPDATE name=VALUES(name), description=VALUES(description), price=VALUES(price), stock=VALUES(stock);

FLUSH PRIVILEGES;
