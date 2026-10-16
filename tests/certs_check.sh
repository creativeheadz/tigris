#!/bin/sh
#
# tests/certs_check.sh - check_certs against a root of its own
#
# A fake root holds an nginx.conf including a site with an expired
# certificate (and a disabled site that must not be read), an apache
# configuration with a certificate expiring soon, a letsencrypt leaf
# reached through an absolute link, a fine certificate, a bare key and
# a CA certificate (both skipped). openssl is a script
# (Tigris_Openssl_Cmd) that answers -text and -checkend from the file
# name, so the logic is tested with or without the real one; when the
# real openssl exists it also reads two certificates it made itself.
# Tigris_Openssl_Cmd set but empty means no openssl (crt003i).
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
cp "$W/tigris.conf" "$W/tigris.conf.base"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

r="$W/root"
mkdir -p "$r/etc/nginx/sites-enabled" "$r/etc/nginx/sites-available" "$r/etc/nginx/ssl" \
  "$r/etc/apache2/sites-enabled" "$r/etc/apache2/ssl" \
  "$r/etc/letsencrypt/live/example.com" "$r/etc/letsencrypt/archive/example.com" \
  "$r/etc/ssl/private"
printf 'events {}\nhttp {\n  include sites-enabled/*;\n}\n' > "$r/etc/nginx/nginx.conf"
printf 'server {\n  listen 443 ssl;\n  ssl_certificate /etc/nginx/ssl/old.pem;\n  ssl_certificate_key /etc/nginx/ssl/old.key;\n}\nserver {\n  listen 443 ssl;\n  ssl_certificate /etc/nginx/ssl/server.key;\n}\n' > "$r/etc/nginx/sites-enabled/site"
printf 'server {\n  listen 443 ssl;\n  ssl_certificate /etc/nginx/hidden/never.pem;\n}\n' > "$r/etc/nginx/sites-available/elsewhere"
mkdir -p "$r/etc/nginx/hidden" && : > "$r/etc/nginx/hidden/never.pem"
printf 'Include sites-enabled/*.conf\n' > "$r/etc/apache2/apache2.conf"
printf '<VirtualHost *:443>\n  SSLCertificateFile /etc/apache2/ssl/soon.pem\n</VirtualHost>\n' > "$r/etc/apache2/sites-enabled/site.conf"
ln -s /etc/letsencrypt/archive/example.com/cert1.pem "$r/etc/letsencrypt/live/example.com/cert.pem"
for f in "$r/etc/nginx/ssl/old.pem" "$r/etc/nginx/ssl/good.pem" "$r/etc/nginx/ssl/server.key" \
  "$r/etc/apache2/ssl/soon.pem" "$r/etc/letsencrypt/archive/example.com/cert1.pem" \
  "$r/etc/ssl/private/ca.pem"
do : > "$f"; done

# openssl from the file name: expired, soon, good, a CA, or unreadable
cat > "$W/ossl" <<'EOF'
#!/bin/sh
# usage here is always: x509 -noout -text -in FILE, or x509 -noout
# -checkend SECS -in FILE
if [ "$3" = -text ]; then file=$5; elif [ "$3" = -checkend ]; then file=$6; else exit 2; fi
case "$3" in
  -text)
    case "$file" in
      *old.pem|*cert1.pem|*never.pem) printf 'Certificate:\n        X509v3 Basic Constraints: critical\n            CA:FALSE\n    Not Before: X\n    Not After : Jan  1 00:00:00 2020 GMT\n' ;;
      *soon.pem) printf 'Certificate:\n            CA:FALSE\n    Not After : Dec  1 00:00:00 2027 GMT\n' ;;
      *ca.pem) printf 'Certificate:\n            CA:TRUE\n    Not After : Dec  1 00:00:00 2030 GMT\n' ;;
      *good.pem) printf 'Certificate:\n            CA:FALSE\n    Not After : Dec  1 00:00:00 2035 GMT\n' ;;
      *) exit 1 ;;
    esac ;;
  -checkend)
    case "$file" in
      *old.pem|*cert1.pem|*never.pem) exit 1 ;;
      *soon.pem) [ "$4" = 0 ] && exit 0 || exit 1 ;;
      *) exit 0 ;;
    esac ;;
esac
EOF
chmod 755 "$W/ossl"

cp "$W/tigris.conf.base" "$W/tigris.conf"
{ echo "Tigris_Sysctl_Root='$r'"; echo "Tigris_Openssl_Cmd='$W/ossl'"; echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_certs ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out"
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -F -c -- "$1" "$W/out"; }

has "--FAIL-- [crt001f] The certificate in \`/etc/nginx/ssl/old.pem' expired on Jan 1 00:00:00 2020 GMT; renew it." &&
  ok "an expired certificate nginx serves: crt001f" || { bad "expired"; cat "$W/out"; }
has "--FAIL-- [crt001f] The certificate in \`/etc/letsencrypt/live/example.com/cert.pem' expired" &&
  ok "a letsencrypt leaf, read through an absolute link: crt001f" || { bad "letsencrypt"; cat "$W/out"; }
has "--WARN-- [crt002w] The certificate in \`/etc/apache2/ssl/soon.pem' expires on Dec 1 00:00:00 2027 GMT, within 30 days; renew it." &&
  ok "apache's certificate, expiring soon: crt002w" || { bad "soon"; cat "$W/out"; }
[ "`count 'good.pem'`" = 0 ] && [ "`count 'server.key'`" = 0 ] && [ "`count 'ca.pem'`" = 0 ] &&
  ok "a fine certificate, a bare key and a CA: nothing" || { bad "skips"; cat "$W/out"; }
[ "`count 'never.pem'`" = 0 ] && ok "a disabled nginx site is not read" || { bad "sites-available"; cat "$W/out"; }
grep -q "$r" "$W/out" && bad "a finding names where the root is on this host" || ok "findings name the root's own paths"

# no openssl: the files are listed, their expiry unknown
cp "$W/tigris.conf.base" "$W/tigris.conf"
{ echo "Tigris_Sysctl_Root='$r'"; echo "Tigris_Openssl_Cmd="; echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_certs ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' > "$W/noossl"
grep -F -q -- '--INFO-- [crt003i] 6 certificate files found, but openssl is not installed, so their expiry is unknown.' "$W/noossl" &&
  grep -q '/etc/nginx/ssl/old.pem' "$W/noossl" &&
  ok "without openssl: crt003i lists the files" || { bad "no openssl"; cat "$W/noossl"; }

# nothing to read: silent, not even the header
mkdir -p "$W/empty/etc"
cp "$W/tigris.conf.base" "$W/tigris.conf"
{ echo "Tigris_Sysctl_Root='$W/empty'"; echo "Tigris_Openssl_Cmd='$W/ossl'"; } >> "$W/tigris.conf"
( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_certs ) 2>&1 | grep '^--' | grep -v '^--CONFIG--' > "$W/empty.out"
if [ -s "$W/empty.out" ]; then bad "empty root"; cat "$W/empty.out"; else ok "no certificates anywhere: silent"; fi

# an offline root (TIGRIS_ROOT, as tigris --root sets it)
R=$W/img
mkdir -p "$R/etc/nginx/sites-enabled" "$R/etc/nginx/ssl"
printf 'events {}\nhttp {\n  include sites-enabled/*;\n}\n' > "$R/etc/nginx/nginx.conf"
printf 'server {\n  listen 443 ssl;\n  ssl_certificate /etc/nginx/ssl/old.pem;\n}\n' > "$R/etc/nginx/sites-enabled/site"
: > "$R/etc/nginx/ssl/old.pem"
cp "$W/tigris.conf.base" "$W/tigris.conf"; echo "Tigris_Openssl_Cmd='$W/ossl'" >> "$W/tigris.conf"
( cd "$W" && TIGRIS_ROOT=$R TIGERHOMEDIR=$W sh ./systems/Linux/2/check_certs ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' > "$W/off"
grep -F -q -- "--FAIL-- [crt001f] The certificate in \`/etc/nginx/ssl/old.pem' expired" "$W/off" &&
  ok "offline root: the expired certificate, by the root's path" || { bad "offline"; cat "$W/off"; }
grep -q "$R" "$W/off" && bad "offline root: a finding names where the root is on this host" || ok "offline root: findings name the root's own paths"

# the real openssl, where there is one: a certificate it made is fine,
# and what is not a certificate is skipped
if command -v openssl >/dev/null 2>&1; then
  G=$W/real
  mkdir -p "$G/etc/nginx/ssl"
  openssl req -x509 -newkey rsa:2048 -keyout "$G/etc/nginx/ssl/k.key" -out "$G/etc/nginx/ssl/good.pem" \
    -days 3650 -nodes -subj '/CN=example.com' >/dev/null 2>&1
  echo "not a certificate" > "$G/etc/nginx/ssl/garbage.pem"
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { echo "Tigris_Sysctl_Root='$G'"; echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_certs ) 2>&1 | grep '^--' | grep -v '^--CONFIG--' > "$W/real.out"
  if [ -s "$W/real.out" ]; then bad "real openssl"; cat "$W/real.out"; else ok "real openssl: a ten-year certificate and a non-certificate are silent"; fi
else
  echo "ok   (no openssl here: the real one is not tested)"
fi

[ $fail -eq 0 ] && echo "PASS"
exit $fail
