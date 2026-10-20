#!/bin/sh
# Wird vom nginx-Entrypoint (/docker-entrypoint.d) beim Start ausgeführt.
# Die Default-Route des Containers zeigt ins Docker-Bridge-Netz; Antworten an Clients
# in anderen LAN-Netzen (VPN, z. B. 192.168.180.x) würden dort per NAT auf die NAS-IP
# umgeschrieben und vom Client verworfen. Daher diese Netze über die FritzBox routen.

# LAN_IP, LAN_GATEWAY und LAN_ROUTES kommen aus .env (siehe docker-compose.yaml).

if [ -z "$LAN_IP" ] || [ -z "$LAN_GATEWAY" ] || [ -z "$LAN_ROUTES" ]; then
    echo "lan-routes: LAN_IP, LAN_GATEWAY oder LAN_ROUTES nicht gesetzt, keine Routen" >&2
    exit 0
fi

dev=$(ip -o -4 addr show | awk -v ip="$LAN_IP" '$4 ~ "^"ip"/" {print $2}')
if [ -z "$dev" ]; then
    echo "lan-routes: keine Schnittstelle mit $LAN_IP gefunden" >&2
    exit 0
fi

for net in $LAN_ROUTES; do
    ip route replace "$net" via "$LAN_GATEWAY" dev "$dev" \
        && echo "lan-routes: $net via $LAN_GATEWAY dev $dev"
done
