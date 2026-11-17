FROM ubuntu:22.04

# Evitar interacción interactiva en tzdata / apt
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    sysbench \
    default-mysql-client \
    curl \
    ca-certificates \
    bc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Mantener el contenedor en espera para recibir ejecuciones mediante docker compose exec
CMD ["sleep", "infinity"]
