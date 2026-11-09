#!/bin/zsh
# Creates the stable self-signed certificate "MenuStats Self Signing" for the app's signature and stores it in the
# repository secrets MENUSTATS_SIGNING_P12 / MENUSTATS_SIGNING_PASSWORD (needs `gh` with admin rights on the repo).
# Run it once: with the same certificate every release keeps the permissions users granted (Full Disk Access).
# The private key is never written to the repository; keep the printed backup folder somewhere safe.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="${REPO:-thomas-addamo/MenuStats}"
OUT="$(mktemp -d)"
PASSWORD="$(openssl rand -hex 24)"
cat > "$OUT/cert.cnf" <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=MenuStats Self Signing
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$OUT/key.pem" -out "$OUT/cert.pem" -days 7300 -config "$OUT/cert.cnf" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$OUT/key.pem" -in "$OUT/cert.pem" -out "$OUT/MenuStats-signing.p12" -passout "pass:$PASSWORD"
rm "$OUT/key.pem" "$OUT/cert.cnf"
base64 -i "$OUT/MenuStats-signing.p12" | gh secret set MENUSTATS_SIGNING_P12 --repo "$REPO"
printf '%s' "$PASSWORD" | gh secret set MENUSTATS_SIGNING_PASSWORD --repo "$REPO"
printf '%s\n' "$PASSWORD" > "$OUT/password.txt"
echo "Certificato salvato nei secret di $REPO. Copia di sicurezza (tienila al sicuro): $OUT"
