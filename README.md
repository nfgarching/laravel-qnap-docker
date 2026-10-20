# Laravel auf QNAP Container Station

Docker-Compose-Setup, mit dem eine Laravel-Anwendung (PHP 8.4) auf einem QNAP-NAS läuft:
nginx + PHP-FPM, Queue-Worker, Laravel Reverb (WebSockets), Redis und ein
Let's-Encrypt-Zertifikat per DNS-01, alles im LAN unter einem eigenen Hostnamen mit eigener
IP-Adresse.

Laravel Sail lässt sich auf QNAP-Geräten mit Kernel 5.10 nicht bauen (siehe
[Stolpersteine](#stolpersteine-auf-qnap)). Dieses Setup nutzt deshalb ein eigenes Image auf
Basis von `php:8.4-fpm-bookworm`.

Getestet auf QTS mit Kernel 5.10.60 (arm64), Container Station mit Docker Compose v2.

## Aufbau

| Service     | Image                     | Aufgabe |
|-------------|---------------------------|---------|
| `app`       | eigenes (`docker/php`)    | PHP-FPM 8.4, Laravel-Code aus `src/` |
| `webserver` | `nginx:alpine`            | HTTPS auf eigener LAN-IP, Reverb-Proxy unter `/app`, Webhook-Port |
| `queue`     | eigenes                   | `php artisan queue:work` |
| `reverb`    | eigenes                   | `php artisan reverb:start` (WebSockets) |
| `redis`     | `redis:7-alpine`          | Cache, Sessions, Queue |
| `lego`      | `goacme/lego`             | Let's-Encrypt-Zertifikat per DNS-01 über acme-dns, Erneuerung alle 12 h |

| Datei | Inhalt |
|-------|--------|
| `docker-compose.yaml` | Services, Netze, Volumes |
| `.env.example` | Werte der Installation: Domain, LAN-IP/MAC/Gateway, ACME-E-Mail, Namen |
| `docker-compose.override.example.yaml` | Beispiel für zusätzliche Mounts (Freigaben des NAS) |
| `docker/php/Dockerfile` | PHP-8.4-FPM-Image (Debian Bookworm) |
| `docker/nginx/templates/default.conf.template` | nginx-Konfiguration, beim Start mit Werten aus `.env` gefüllt |
| `docker/nginx/lan-routes.sh` | Routen für andere LAN-/VPN-Netze über den Router |
| `docker/nginx/reload-certs.sh` | lädt nginx alle 6 h neu, damit erneuerte Zertifikate greifen |
| `docker/lego/renew.sh` | Schleife im lego-Container |
| `docker/certs/make-certs.sh` | optionale interne CA für Kurznamen und IP |
| `start.sh` | `docker compose up -d` mit QNAP-Workarounds |
| `src/` | die Laravel-Anwendung (nicht Teil dieses Repositorys) |

## Stolpersteine auf QNAP

1. **Container Station überschreibt `$HOME`.** Der Docker-CLI-Wrapper setzt `HOME` auf ein
   Verzeichnis, in das normale Benutzer nicht schreiben dürfen. `docker` und
   `docker compose` scheitern dann mit `permission denied`. Abhilfe: `DOCKER_CONFIG` auf ein
   beschreibbares Verzeichnis setzen, dauerhaft in `~/.profile`:

   ```sh
   export DOCKER_CONFIG=/share/homes/$(id -un)/.docker
   ```

   `start.sh` setzt den Wert selbst.

2. **Debian Trixie läuft nicht auf Kernel 5.10.** `php:8.4-fpm` ohne Suffix basiert auf
   Debian Trixie (glibc 2.41). Die nutzt den Syscall `fchmodat2`, den der QNAP-Kernel 5.10.60
   nicht kennt: der Build bricht mit `Bad address` ab, z. B. bei
   `fchmod() of /etc/credstore failed`. Daran scheitert auch das Sail-Image. Abhilfe: ein
   Image mit dem Suffix `-bookworm` (glibc 2.36). Bullseye ist keine Alternative mehr, seit
   dem Ende des LTS (08/2026) liefert `bullseye-security` für arm64 nur noch 404.

3. **`dnsmasg add fail` beim ersten Start.** `docker compose up` bricht gelegentlich mit
   `dnsmasg add fail : failure` (qnetwork-tool) ab, während das Netz schon angelegt wird. Das
   ist vorübergehend, ein zweiter Aufruf läuft durch. `start.sh` wiederholt ihn automatisch.
   Hilft das nicht: `docker network rm <projekt>_default` und erneut starten.

4. **Ports 80 und 443 gehören QTS.** Der Webserver bekommt deshalb im Netz `lan` (QNAP-Treiber
   `qnet`, eine Bridge auf `eth0`) eine eigene IP-Adresse im LAN. Das funktioniert wie macvlan:
   **das NAS selbst erreicht diese IP nicht**, andere Geräte im LAN schon. Tests vom NAS aus
   daher aus einem Container heraus (siehe [Prüfen](#prüfen)).

5. **Antworten an andere Netze gehen verloren.** Die Default-Route des Webservers zeigt ins
   Docker-Netz. Antworten an Clients aus anderen Netzen (z. B. VPN `192.168.180.0/24`) würden
   dort per NAT auf die NAS-IP umgeschrieben und vom Client verworfen. `lan-routes.sh` leitet
   die Netze aus `LAN_ROUTES` deshalb über den Router.

6. **Dateirechte im Bind-Mount.** PHP-FPM schreibt als `www-data` nach `src/storage` und
   `src/bootstrap/cache`. Das Image setzt die UID/GID von `www-data` deshalb auf `HOST_UID` und
   `HOST_GID` aus `.env` (Besitzer von `src/`, ermitteln mit `id -u` und `id -g`).

7. **Symlinks als Mount-Quelle.** `/share/<Freigabe>` ist auf QNAP ein Symlink. Als Quelle eines
   Bind-Mounts den realen Pfad unter `/share/CACHEDEV1_DATA/` angeben.

## Installation

Auf dem NAS per SSH. Auf dem NAS selbst sind weder PHP noch Composer oder Node installiert,
alle Befehle laufen in Containern.

### 1. Repository und Werte

```sh
cd /share/CACHEDEV1_DATA/Container/container-station-data/application
git clone https://github.com/<benutzer>/<repo>.git laravel
cd laravel
cp .env.example .env
```

In `.env` mindestens `APP_DOMAIN`, die `LAN_*`-Werte, `NGINX_REDIRECT_HOSTS`, `ACME_EMAIL` und
`HOST_UID`/`HOST_GID` anpassen. `LAN_IP` muss außerhalb des DHCP-Bereichs des Routers liegen.
`LAN_MAC` ist eine lokal verwaltete Adresse; mit `02:42` und der IP in Hex (z. B.
`192.168.178.100` → `02:42:c0:a8:b2:64`) bleibt sie eindeutig.

### 2. Laravel-Anwendung in `src/`

Eine vorhandene Anwendung nach `src/` klonen, oder eine neue anlegen:

```sh
mkdir src
export DOCKER_CONFIG=/share/homes/$(id -un)/.docker
docker compose build app
docker compose run --rm --no-deps -u www-data -e COMPOSER_HOME=/tmp/composer \
    app composer create-project laravel/laravel .
```

### 3. Zertifikate

nginx startet erst, wenn alle Zertifikate vorhanden sind, auf die es verweist. lego braucht
nginx nicht (DNS-01) und läuft deshalb zuerst:

```sh
docker/certs/make-certs.sh       # interne CA + Zertifikat für NGINX_REDIRECT_HOSTS
mkdir -p docker/letsencrypt      # vorher anlegen, sonst legt Docker es als root an
# docker/certs/acme-dns.json anlegen und DNS eintragen, siehe „HTTPS mit Let's Encrypt“
docker compose up -d lego
docker logs -f laravel_lego      # warten, bis das Zertifikat ausgestellt ist
```

### 4. Starten

```sh
./start.sh --build
```

### 5. Laravel einrichten

```sh
docker exec -u www-data laravel_app composer install      # nur bei geklonter App
docker exec -u www-data laravel_app php artisan key:generate
docker exec -u www-data laravel_app php artisan migrate --force
docker exec -u www-data laravel_app php artisan install:broadcasting --reverb   # falls noch nicht vorhanden
```

Die Container heißen `<CONTAINER_PREFIX>_app`, `_web`, `_queue`, `_reverb`, `_redis`, `_lego`.

Frontend-Assets mit einem Wegwerf-Container bauen (Vite 7 braucht Node ≥ 20, das PHP-Image
hat kein Node):

```sh
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD/src:/app" -w /app \
    -e HOME=/tmp node:22-alpine sh -c 'npm install && npm run build'
```

### 6. `src/.env` der Anwendung

```dotenv
APP_URL=https://laravel.example.com
SESSION_SECURE_COOKIE=true

CACHE_STORE=redis
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis
REDIS_CLIENT=phpredis
REDIS_HOST=redis
REDIS_QUEUE_RETRY_AFTER=1300   # > längste Job-Laufzeit, Vorgabe 90 s

BROADCAST_CONNECTION=reverb
REVERB_SERVER_HOST=reverb      # App und Queue erreichen Reverb im Docker-Netz
REVERB_PORT=8081               # = --port des reverb-Service
REVERB_SCHEME=http
REVERB_HOST=laravel.example.com
VITE_REVERB_HOST="${REVERB_HOST}"
VITE_REVERB_PORT=443           # der Browser kommt über nginx (wss://…/app)
VITE_REVERB_SCHEME=https
```

`REVERB_SERVER_HOST` muss in `config/broadcasting.php` als Host der Reverb-Verbindung
ausgewertet werden, z. B. `'host' => env('REVERB_SERVER_HOST', env('REVERB_HOST'))`.
Die `VITE_*`-Werte werden beim Asset-Build eingebacken: nach jeder Änderung Assets neu bauen.

Danach Container neu erzeugen, damit Queue und Reverb die Werte lesen:

```sh
docker compose up -d --force-recreate app queue reverb
```

## Netzwerk und DNS

- **Eigene IP:** Der Webserver erscheint im LAN als eigenes Gerät mit `LAN_IP` und `LAN_MAC`.
  Im Router kann man ihm einen Namen geben; bei einer FritzBox lösen dann `<name>` und
  `<name>.fritz.box` auf.
- **Webhook-Port:** Auf der NAS-IP ist nur `APP_PORT` (Vorgabe 8026) veröffentlicht. Dort
  beantwortet nginx ausschließlich `/api/webhooks/*`, alles andere leitet es auf `APP_DOMAIN`
  um. Gedacht für Webhooks, die ein öffentlicher Server ins LAN weiterreicht.
- **Öffentlicher DNS-Name:** Für ein Let's-Encrypt-Zertifikat braucht die App einen Namen in
  einer eigenen Domain. Ein A-Eintrag darf auf die private `LAN_IP` zeigen; von außen ist die
  App damit trotzdem nicht erreichbar.
- **DNS-Rebind-Schutz:** Viele Router (z. B. die FritzBox) verwerfen DNS-Antworten mit privaten
  IPs. Den Namen dort als Ausnahme eintragen (FritzBox: Heimnetz → Netzwerk →
  Netzwerkeinstellungen → DNS-Rebind-Schutz).

## HTTPS mit Let's Encrypt

Weil die App aus dem Internet nicht erreichbar ist, scheiden HTTP- und TLS-Challenge aus. Hat
der DNS-Anbieter keine API, delegiert ein CNAME die DNS-01-Challenge an
[acme-dns](https://github.com/joohoi/acme-dns). Der öffentliche Dienst `auth.acme-dns.io`
genügt.

1. Bei acme-dns registrieren:

   ```sh
   curl -s -X POST https://auth.acme-dns.io/register
   ```

2. Die Antwort als `docker/certs/acme-dns.json` speichern, mit `APP_DOMAIN` als Schlüssel,
   Rechte `600` (die Datei ist geheim und nicht versioniert):

   ```json
   {
     "laravel.example.com": {
       "username": "…",
       "password": "…",
       "subdomain": "…",
       "fulldomain": "….auth.acme-dns.io",
       "allowfrom": []
     }
   }
   ```

3. Beim DNS-Anbieter eintragen:

   | Name                          | Typ   | Wert                         |
   |-------------------------------|-------|------------------------------|
   | `laravel`                     | A     | `LAN_IP`                     |
   | `_acme-challenge.laravel`     | CNAME | `fulldomain` aus Schritt 2   |

4. `mkdir -p docker/letsencrypt`, `docker compose up -d lego`, dann
   `docker logs -f <prefix>_lego`. lego holt das Zertifikat
   nach `docker/letsencrypt/certificates/` und erneuert es, wenn es fällig ist. Für die
   DNS-Prüfung nutzt es `1.1.1.1` und `9.9.9.9`, weil Router private Antworten filtern.
   nginx lädt das Zertifikat alle 6 Stunden neu; beim ersten Mal von Hand:
   `docker exec <prefix>_web nginx -s reload`.

Sichern: `docker/certs/acme-dns.json` und `docker/letsencrypt/accounts/`. Vor Experimenten
die Staging-Umgebung nutzen (`--server letsencrypt-staging`), wegen der Rate-Limits.

### Interne CA (optional)

`make-certs.sh` stellt mit einer eigenen CA ein Zertifikat für die Namen und IPs in
`NGINX_REDIRECT_HOSTS` aus. nginx nutzt es nur, um diese Adressen (Kurzname, Router-Name,
IP) auf `APP_DOMAIN` umzuleiten. Geräte, die `http://<LAN_IP>/ca.crt` als
Stammzertifikat importiert haben, sehen dabei keine Warnung. Wer die Umleitung nicht
braucht, entfernt den zweiten `listen 443`-Block in der nginx-Vorlage und die
`docker/certs`-Mounts.

## Redis, Queue und Reverb

- **Redis** ist nur im Docker-Netz erreichbar (kein Port-Mapping, daher ohne Passwort). Wird
  er je freigegeben, `--requirepass` setzen.
- **`volatile-lru`** verdrängt bei vollem Speicher nur Schlüssel mit Ablaufzeit (Cache,
  Sessions), nie Queue-Jobs. Nicht auf `allkeys-lru` ändern, solange die Queue in Redis liegt.
- **`--appendonly yes`** plus Volume: Sessions und Jobs überstehen einen Neustart.
- **Mehrere Instanzen an einer Datenbank:** Mit `QUEUE_CONNECTION=database` teilen sie sich die
  Tabelle `jobs`, und der Worker der einen Instanz holt Jobs der anderen ab. Die Redis-Queue ist
  pro Instanz lokal. Ebenso nötig: derselbe `APP_KEY` auf allen Instanzen, sonst scheitern
  `encrypted`-Casts mit „The MAC is invalid.“.
- **`queue:work`** hält den Code im Speicher: nach einem Deploy
  `docker exec -u www-data <prefix>_app php artisan queue:restart`. `--max-time=3600` startet
  den Worker zusätzlich stündlich neu. `--tries=1` und `--timeout=300` an die eigenen Jobs
  anpassen; `REDIS_QUEUE_RETRY_AFTER` muss größer als `--timeout` sein.
- **Artisan auf dem Host** gibt es nicht; der Name `redis` existiert ohnehin nur im Docker-Netz.
  Befehle mit `-u www-data` im Container ausführen. Als root angelegte Cache-Dateien kann
  PHP-FPM später nicht überschreiben.

## Zusätzliche Mounts

Freigaben des NAS, die die App lesen oder beschreiben soll, gehören in eine
`docker-compose.override.yaml` (Vorlage: `docker-compose.override.example.yaml`).
`docker compose` liest sie automatisch mit. `app`, `queue` und `reverb` brauchen dieselben
Mounts.

## PHP-Image

`docker/php/Dockerfile` enthält neben den üblichen Laravel-Extensions (`pdo_mysql`,
`pdo_sqlite`, `mbstring`, `intl`, `gd`, `zip`, `bcmath`, `exif`, `pcntl`, `redis`) einige
Werkzeuge, die nicht jede Anwendung braucht. Nicht benötigte Blöcke einfach entfernen:

| Block | Wofür |
|-------|-------|
| `ocrmypdf`, `tesseract-ocr-deu`, jbig2 (aus dem Quellcode, in Bookworm nicht paketiert) | Texterkennung in PDFs |
| `imagick` + gelockerte ImageMagick-Policy für PDF | `spatie/pdf-to-image` |
| `imap` (PECL, seit PHP 8.4 kein Core-Modul) | `webklex/php-imap`, MIME-kodierte Header |
| `ftp` | FTP-Dateisysteme |

Neue Blöcke möglichst unten anfügen: Docker baut dann nur die Schichten ab der Änderung neu,
der jbig2-Build (mehrere Minuten auf einem NAS) kommt aus dem Cache.

## Prüfen

Vom NAS aus ist `LAN_IP` nicht erreichbar, daher aus dem Webserver-Container:

```sh
docker exec <prefix>_web curl -s -o /dev/null -w "%{http_code}\n" \
    --resolve laravel.example.com:443:127.0.0.1 https://laravel.example.com/
docker exec <prefix>_redis redis-cli ping
docker exec -u www-data <prefix>_app php artisan tinker --execute="Cache::put('t', 1, 60); dump(Cache::get('t'));"
openssl x509 -in docker/letsencrypt/certificates/laravel.example.com.crt -noout -issuer -enddate
```

## Fehlersuche

| Beobachtung | Ursache / Abhilfe |
|-------------|-------------------|
| `permission denied` bei `docker` | `DOCKER_CONFIG` nicht gesetzt (Stolperstein 1) |
| Build: `Bad address` | Image ohne `-bookworm` (Stolperstein 2) |
| `dnsmasg add fail` | erneut starten (Stolperstein 3) |
| Name löst im LAN nicht auf | DNS-Rebind-Schutz des Routers |
| VPN-Clients bekommen keine Antwort | `LAN_ROUTES` deckt deren Netz nicht ab |
| lego: `NXDOMAIN`, TXT nicht gefunden | CNAME `_acme-challenge.<name>` prüfen |
| lego: `401`/`403` von acme-dns | `acme-dns.json` falsch oder Konto gelöscht, neu registrieren |
| `ERR_CERT_DATE_INVALID` | Erneuerung fehlgeschlagen, `docker logs <prefix>_lego` |
| `Connection refused` für `redis` | Redis-Container läuft nicht, oder Befehl lief auf dem Host |
| Jobs laufen doppelt | `REDIS_QUEUE_RETRY_AFTER` fehlt (Vorgabe 90 s) |
| Live-Updates fehlen | Reverb läuft nicht, `REVERB_SERVER_HOST` falsch, oder Assets nach Änderung der `VITE_*`-Werte nicht neu gebaut |
| `Permission denied` in `storage/` | `HOST_UID`/`HOST_GID` passen nicht zum Besitzer von `src/`, Image neu bauen |

## Nützliche Befehle

```sh
./start.sh                       # starten
./start.sh --build               # Image neu bauen und starten
docker compose ps
docker compose logs -f webserver app queue
docker exec -u www-data <prefix>_app php artisan optimize:clear
docker compose down              # stoppen
```

## Lizenz

MIT, siehe [LICENSE](LICENSE).
