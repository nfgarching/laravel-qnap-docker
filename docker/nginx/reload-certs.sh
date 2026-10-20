#!/bin/sh
# Wird vom nginx-Entrypoint (/docker-entrypoint.d) beim Start ausgeführt.
# Der lego-Container erneuert das Let's-Encrypt-Zertifikat, kann nginx aber nicht neu laden.
# Daher lädt nginx seine Konfiguration (und damit das Zertifikat) alle 6 Stunden selbst neu.

(
    while sleep 21600; do
        nginx -s reload
    done
) &
