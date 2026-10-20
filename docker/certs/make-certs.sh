#!/bin/sh
# Interne CA und Server-Zertifikat für die Redirect-Namen (nur LAN).
#
#   ./make-certs.sh          Server-Zertifikat (neu) ausstellen; legt die CA beim ersten Aufruf an
#
# Namen und IPs aus NGINX_REDIRECT_HOSTS in ../../.env; der erste Eintrag wird CN.
# Die CA (ca.key/ca.crt) bleibt bei Erneuerungen erhalten, damit das auf den Geräten
# importierte ca.crt gültig bleibt. ca.key nie weitergeben.
# Danach: docker compose restart webserver

SERVER_DAYS=825   # Apple akzeptiert max. 825 Tage

cd "$(dirname "$0")" || exit 1

if [ ! -f ../../.env ]; then
    echo "../../.env fehlt (Vorlage: .env.example)" >&2
    exit 1
fi
set -a
. ../../.env
set +a

if [ -z "$NGINX_REDIRECT_HOSTS" ]; then
    echo "NGINX_REDIRECT_HOSTS in .env setzen" >&2
    exit 1
fi

umask 077

if [ ! -f ca.key ]; then
    openssl req -utf8 -x509 -new -nodes -newkey rsa:4096 -sha256 -days 3650 \
        -keyout ca.key -out ca.crt \
        -subj "/O=${CA_NAME:-Laravel}/CN=${CA_NAME:-Laravel} interne CA" \
        -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" || exit 1
    echo "CA angelegt: ca.crt (auf allen Geräten als vertrauenswürdige Stammzertifizierungsstelle importieren)"
fi

# subjectAltName: IPv4-Adressen als IP:, alles andere als DNS:
san=""
for host in $NGINX_REDIRECT_HOSTS; do
    case "$host" in
        *[!0-9.]*) entry="DNS:$host" ;;
        *)         entry="IP:$host" ;;
    esac
    san="${san:+$san,}$entry"
done
set -- $NGINX_REDIRECT_HOSTS
cn="$1"

cat > server.ext <<EOF
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=$san
EOF

openssl req -new -nodes -newkey rsa:2048 -sha256 \
    -keyout server.key -out server.csr -subj "/CN=$cn" || exit 1
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -days "$SERVER_DAYS" -sha256 -extfile server.ext -out server.crt || exit 1
rm -f server.csr server.ext

# nginx (Container) muss Schlüssel und Zertifikat lesen können.
chmod 644 ca.crt server.crt
chmod 640 server.key

openssl x509 -in server.crt -noout -subject -enddate -ext subjectAltName
