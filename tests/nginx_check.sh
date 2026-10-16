#!/bin/sh
#
# tests/nginx_check.sh - check_nginx against a root of its own
#
# A fake root with a bad server (weak protocols and ciphers, an open
# key, a missing certificate, no logging, no HSTS, listings on, and a
# regex location plus a quoted-braces if that must not confuse the
# block tracking), a clean HTTPS server, a plain HTTP one, a
# group-readable key, and a disabled site that must not be read. Then
# a root for the http scope (logging off and HSTS there), one for the
# compiled-in main path and user root, and an offline root.
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
join() {
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--'
}
run() {  # run ROOT OUTFILE: check_nginx against ROOT
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { echo "Tigris_Sysctl_Root='$1'"; echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_nginx ) 2>&1 | join > "$2"
}

r="$W/root"
mkdir -p "$r/etc/nginx/sites-enabled" "$r/etc/nginx/sites-available" "$r/etc/nginx/ssl"
printf '# nginx\nuser nginx;\n\nevents { worker_connections 1024; }\nhttp {\n  include sites-enabled/*;\n  server_tokens on;\n  ssl_protocols SSLv3 TLSv1.2;\n  error_log /dev/null;\n}\n' > "$r/etc/nginx/nginx.conf"
cat > "$r/etc/nginx/sites-enabled/10-bad" <<'EOF'
server {
  listen 443 ssl;
  server_name bad.example;
  access_log off;
  ssl_certificate /etc/nginx/ssl/missing.pem;
  ssl_certificate_key /etc/nginx/ssl/open.key;
  ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
  ssl_ciphers 'DEFAULT:RC4-MD5';
  location ~ ^/fingerprint-[0-9a-f]{32}\.js$ {
  }
  if ($arg_x ~ "^{.*}$") { return 444; }
  location /images/ {
    autoindex on;
  }
}
EOF
cat > "$r/etc/nginx/sites-enabled/20-good" <<'EOF'
server {
  listen 443 ssl;
  server_name good.example;
  access_log /var/log/nginx/good.log;
  ssl_certificate /etc/nginx/ssl/good.pem;
  ssl_certificate_key /etc/nginx/ssl/good.key;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers 'HIGH:!aNULL:!MD5';
  add_header Strict-Transport-Security "max-age=31536000";
}
EOF
printf 'server {\n  listen 80;\n  server_name plain.example;\n  access_log /var/log/nginx/plain.log;\n}\n' > "$r/etc/nginx/sites-enabled/30-plain"
printf 'server {\n  listen 443 ssl;\n  server_name grp.example;\n  access_log /var/log/nginx/grp.log;\n  ssl_certificate /etc/nginx/ssl/good.pem;\n  ssl_certificate_key /etc/nginx/ssl/grp.key;\n  add_header Strict-Transport-Security "max-age=1";\n}\n' > "$r/etc/nginx/sites-enabled/40-grp"
printf 'server_tokens on;\nserver {\n  listen 443 ssl;\n  server_name ignored.example;\n  access_log off;\n  ssl_protocols SSLv3;\n}\n' > "$r/etc/nginx/sites-available/ignored"
: > "$r/etc/nginx/ssl/good.pem"; : > "$r/etc/nginx/ssl/good.key"; chmod 600 "$r/etc/nginx/ssl/good.key"
: > "$r/etc/nginx/ssl/open.key"; chmod 644 "$r/etc/nginx/ssl/open.key"
: > "$r/etc/nginx/ssl/grp.key"; chmod 640 "$r/etc/nginx/ssl/grp.key"
run "$r" "$W/out"
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -F -c -- "$1" "$W/out"; }

has "[ngx001w] server_tokens is on (/etc/nginx/nginx.conf line 7): every response and error page advertises the nginx version." &&
  [ "`count 'ngx001w'`" = 1 ] &&
  ok "server_tokens on, with its line, once" || { bad "tokens"; cat "$W/out"; }
has "[ngx005f] ssl_protocols in /etc/nginx/nginx.conf line 8 allows SSLv3: broken protocols, disabled in every client years ago." &&
  ok "SSLv3 at http scope: ngx005f" || { bad "sslv3"; cat "$W/out"; }
has "[ngx012w] Errors are thrown away (error_log /dev/null in /etc/nginx/nginx.conf line 9): failures leave no trace." &&
  ok "error_log to /dev/null: ngx012w" || { bad "error_log"; cat "$W/out"; }
has "[ngx006w] ssl_protocols in /etc/nginx/sites-enabled/10-bad line 7 allows TLSv1, TLSv1.1: deprecated since 2021; TLS 1.2 is the floor." &&
  ok "TLS 1.0 and 1.1, both named: ngx006w" || { bad "tls"; cat "$W/out"; }
has "[ngx007w] ssl_ciphers in /etc/nginx/sites-enabled/10-bad line 8 names weak ciphers (RC4-MD5): clients can negotiate down to them." &&
  ok "a weak cipher offered: ngx007w" || { bad "ciphers"; cat "$W/out"; }
has "[ngx002w] The server \`bad.example' never logs requests (/etc/nginx/sites-enabled/10-bad line 4): without logs an intrusion leaves no trace here." &&
  ok "access_log off: ngx002w names the server and the line" || { bad "access_log"; cat "$W/out"; }
has "[ngx003f] The TLS key \`/etc/nginx/ssl/open.key' is readable by anyone:" &&
  ok "a world-readable key: ngx003f" || { bad "open key"; cat "$W/out"; }
has "[ngx011w] The certificate \`/etc/nginx/ssl/missing.pem' for the server \`bad.example' (/etc/nginx/sites-enabled/10-bad line 5) is not there:" &&
  ok "a missing certificate: ngx011w" || { bad "missing cert"; cat "$W/out"; }
has "[ngx009w] Directory listings are on for the server \`bad.example' (autoindex in /etc/nginx/sites-enabled/10-bad line 13):" &&
  ok "autoindex past a regex location: ngx009w" || { bad "autoindex"; cat "$W/out"; }
has "[ngx010i] The server \`bad.example' serves HTTPS without Strict-Transport-Security: first visits can be silently downgraded." &&
  ok "no HSTS: ngx010i" || { bad "hsts"; cat "$W/out"; }
uid=`id -u`
if [ "$uid" != 0 ]; then
  has "[ngx004w] The TLS key \`/etc/nginx/ssl/grp.key' is readable by group" &&
    ok "a group-readable key: ngx004w" || { bad "group key"; cat "$W/out"; }
else
  grep -q 'ngx004w' "$W/out" && { bad "group key as root"; cat "$W/out"; } || ok "as root the group-readable key is root's alone: nothing"
fi
[ "`count 'good.example'`" = 0 ] && [ "`count 'plain.example'`" = 0 ] && [ "`count 'ignored.example'`" = 0 ] &&
  ok "the clean servers and the disabled site: nothing" || { bad "clean"; cat "$W/out"; }
grep -q "$r" "$W/out" && bad "a finding names where the root is on this host" || ok "findings name the root's own paths"

# the http scope: logging off and HSTS there
H=$W/http
mkdir -p "$H/etc/nginx/sites-enabled" "$H/etc/nginx/ssl"
printf 'user nginx;\nevents {}\nhttp {\n  include sites-enabled/*;\n  server_tokens off;\n  access_log off;\n  error_log /var/log/nginx/error.log;\n  add_header Strict-Transport-Security "max-age=1";\n}\n' > "$H/etc/nginx/nginx.conf"
printf 'server {\n  listen 443 ssl;\n  server_name a.example;\n  ssl_certificate /etc/nginx/ssl/good.pem;\n  ssl_certificate_key /etc/nginx/ssl/good.key;\n}\n' > "$H/etc/nginx/sites-enabled/a"
printf 'server {\n  listen 443 ssl;\n  server_name b.example;\n  access_log syslog:server=127.0.0.1;\n  add_header X-Frame-Options SAMEORIGIN;\n  ssl_certificate /etc/nginx/ssl/good.pem;\n  ssl_certificate_key /etc/nginx/ssl/good.key;\n}\n' > "$H/etc/nginx/sites-enabled/b"
: > "$H/etc/nginx/ssl/good.pem"; : > "$H/etc/nginx/ssl/good.key"; chmod 600 "$H/etc/nginx/ssl/good.key"
run "$H" "$W/http.out"
grep -F -q "[ngx002w] The server \`a.example' never logs requests (/etc/nginx/nginx.conf line 6):" "$W/http.out" &&
  grep -F -q "[ngx010i] The server \`b.example' serves HTTPS without Strict-Transport-Security:" "$W/http.out" &&
  [ "`grep -c '^--' "$W/http.out"`" = 2 ] &&
  ok "http scope: off inherited, HSTS inherited, headers replaced" || { bad "http scope"; cat "$W/http.out"; }

# the compiled-in main path, and workers as root
F=$W/fallback
mkdir -p "$F/usr/local/nginx/conf"
printf 'user root;\nevents {}\nhttp {\n  server_tokens off;\n  server { listen 80; }\n}\n' > "$F/usr/local/nginx/conf/nginx.conf"
run "$F" "$W/fb.out"
grep -F -q "[ngx008f] nginx's workers run as root (user root in /usr/local/nginx/conf/nginx.conf line 1):" "$W/fb.out" &&
  [ "`grep -c '^--' "$W/fb.out"`" = 1 ] &&
  ok "fallback main path, user root, single-line server" || { bad "fallback"; cat "$W/fb.out"; }

# an offline root (TIGRIS_ROOT, as tigris --root sets it)
R=$W/img
mkdir -p "$R/etc/nginx/sites-enabled"
printf 'events {}\nhttp {\n  include sites-enabled/*;\n}\n' > "$R/etc/nginx/nginx.conf"
printf 'server {\n  listen 443 ssl;\n  ssl_protocols TLSv1;\n}\n' > "$R/etc/nginx/sites-enabled/site"
cp "$W/tigris.conf.base" "$W/tigris.conf"; echo "Tigris_Show_INFO_Msgs=Y" >> "$W/tigris.conf"
( cd "$W" && TIGRIS_ROOT=$R TIGERHOMEDIR=$W sh ./systems/Linux/2/check_nginx ) 2>&1 | join > "$W/off"
grep -F -q '[ngx006w] ssl_protocols in /etc/nginx/sites-enabled/site line 3 allows TLSv1:' "$W/off" &&
  ok "offline root: TLS 1.0" || { bad "offline"; cat "$W/off"; }
grep -q "$R" "$W/off" && bad "offline root: a finding names where the root is on this host" || ok "offline root: findings name the root's own paths"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
