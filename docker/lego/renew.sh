#!/bin/sh
# Holt bzw. erneuert das Let's-Encrypt-Zertifikat für $LEGO_DOMAINS per DNS-01 über acme-dns
# (CNAME _acme-challenge.<host> beim DNS-Anbieter → auth.acme-dns.io, Zugangsdaten in acme-dns.json).
# "lego run" erneuert nur, wenn das Zertifikat fällig ist (ein Drittel Restlaufzeit).
# nginx lädt das Zertifikat selbst periodisch neu (docker/nginx/reload-certs.sh).

while true; do
    /lego run --path /data \
        --accept-tos \
        --dns acmedns \
        --dns.resolvers 1.1.1.1:53,9.9.9.9:53 \
        --log.format text \
        || echo "lego: Fehler, nächster Versuch in 12 Stunden" >&2
    sleep 43200
done
