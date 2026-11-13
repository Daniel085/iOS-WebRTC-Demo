#!/bin/sh
# Self-signed TLS certificate for Asterisk's WSS transport (prototype only).
#   ./make-certs.sh                 -> CN=localhost
#   ./make-certs.sh 192.168.4.20    -> also valid for that IP (phones on the LAN)
#   ./make-certs.sh pbx.example.com -> also valid for that host name
# Browsers must trust it once: open https://<host>:8089/ws and accept the warning.
# Production: use real certificates (Let's Encrypt) and point http.conf at them.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
NAME="${1:-localhost}"
case "$NAME" in
  *[!0-9.]*) ALT="DNS:$NAME,DNS:localhost,IP:127.0.0.1" ;;
  *)         ALT="IP:$NAME,DNS:localhost,IP:127.0.0.1" ;;
esac
openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
  -keyout "$DIR/privkey.pem" -out "$DIR/fullchain.pem" \
  -subj "/CN=$NAME" -addext "subjectAltName=$ALT"
# The asterisk user inside the container must be able to read the key.
chmod 644 "$DIR/privkey.pem" "$DIR/fullchain.pem"
echo "Wrote $DIR/fullchain.pem and $DIR/privkey.pem (CN=$NAME, SAN=$ALT)"
