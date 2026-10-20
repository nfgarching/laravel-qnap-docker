#!/bin/sh
# Startet die Laravel-Umgebung (nginx + PHP-FPM, Reverb, Queue, Redis, lego) per Docker Compose.
# Aufruf: ./start.sh [--build]

# Container Station setzt HOME auf ein nicht beschreibbares Verzeichnis (siehe README.md).
export DOCKER_CONFIG="${DOCKER_CONFIG:-/share/homes/$(id -un)/.docker}"

cd "$(dirname "$0")" || exit 1

if [ "$1" = "--build" ]; then
    docker compose build || exit 1
fi

# Der erste Start bricht auf dem QNAP gelegentlich mit "dnsmasg add fail" ab (transient).
if ! docker compose up -d; then
    echo "Erneuter Versuch ..."
    sleep 3
    docker compose up -d || exit 1
fi

docker compose ps
