# ==============================================================================
# MAKEFILE — PROYECTO 4: BALANCEO DE CARGAS MYSQL CON PROXYSQL
# Servicios Telemáticos — Universidad Autónoma de Occidente (2026-02)
# ==============================================================================

.PHONY: help up down restart status logs sync demo test1 test2 test3 test4 test5 test6 test7 test8 test9

help:
	@echo "Comandos disponibles para la sustentación y evaluación:"
	@echo "  make up       - Despliega todo el clúster con Docker Compose (Zero-Flake)"
	@echo "  make down     - Detiene los contenedores y elimina volúmenes de datos"
	@echo "  make status   - Muestra el estado de salud de todos los contenedores"
	@echo "  make sync     - Fuerza la sincronización RUNTIME y DISK en ProxySQL"
	@echo "  make demo     - Ejecuta la suite completa de las 9 pruebas automatizadas"
	@echo "  make test1    - Prueba 1: Query Routing y Read/Write Split"
	@echo "  make test2    - Prueba 2: Caída forzada del Maestro y Resiliencia"
	@echo "  make test3    - Prueba 3: Benchmark Sysbench comparativo (1M filas)"
	@echo "  make test4    - Prueba 4: Saturación de Conexiones y Multiplexing"
	@echo "  make test5    - Prueba 5: Escalamiento en Caliente (mysql-slave-3)"
	@echo "  make test6    - Prueba 6: Aceleración con Query Cache en RAM"
	@echo "  make test7    - Prueba 7: Integración E2E con API REST Flask"
	@echo "  make test8    - Prueba 8: Cifrado TLS/SSL X.509 en tránsito"
	@echo "  make test9    - Prueba 9: Escenarios Paramétricos de Cargas y Pesos"

up:
	docker compose up -d --build
	@echo "Esperando que los servicios alcancen estado saludable..."
	docker compose ps

down:
	docker compose --profile scale down -v --remove-orphans

restart: down up

status:
	docker compose ps

logs:
	docker compose logs -f

sync:
	docker compose exec proxysql bash /scripts/sync-runtime.sh

test1:
	docker compose exec sysbench bash /workspace/scripts/test1_query_routing.sh proxysql

test2:
	docker compose exec sysbench bash /workspace/scripts/test2_master_failover.sh proxysql

test3:
	docker compose exec sysbench bash /workspace/scripts/test3_sysbench_benchmark.sh

test4:
	docker compose exec sysbench bash /workspace/scripts/test4_connection_pooling.sh proxysql

test5:
	docker compose exec sysbench bash /workspace/scripts/test5_hot_scale_slave3.sh proxysql

test6:
	docker compose exec sysbench bash /workspace/scripts/test6_query_cache.sh proxysql

test7:
	docker compose exec sysbench bash /workspace/scripts/test7_flask_e2e.sh app-flask

test8:
	docker compose exec sysbench bash /workspace/scripts/test8_tls_security.sh proxysql

test9:
	docker compose exec sysbench bash /workspace/scripts/test9_parametric_scenarios.sh proxysql

demo:
	docker compose exec sysbench bash /workspace/scripts/run_all_demos.sh
