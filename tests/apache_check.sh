#!/bin/sh
#
# tests/apache_check.sh - check_apache on offline roots
#
# Seven roots: a Debian layout with everything on (symlinks, CGI,
# listings, an open proxy, an open status page); a WebDAV directory;
# a hardened host (Require-denied /, localhost-only status); a 2.2
# host with / properly closed and server-info allowed to all; an
# open / block; a RHEL host listening bare and one bound; and an
# empty root, where nothing is said. INFO findings only show with
# Tiger_Show_INFO_Msgs=Y. Runs as a user and as root; the fixtures
# read the same for both.
#
TIGER=${TIGER:-`cd "\`dirname \"$0\"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
cp "$W/tigerrc" "$W/tigerrc.base"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run() {  # run ROOT OUTFILE: check_apache with ROOT as the audited system
  cp "$W/tigerrc.base" "$W/tigerrc"
  { echo "Tiger_Show_INFO_Msgs=Y"; } >> "$W/tigerrc"
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./scripts/check_apache ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }

D=$W/deb; mkdir -p "$D/etc/apache2/mods-enabled" "$D/etc/apache2/sites-enabled"
cat > "$D/etc/apache2/apache2.conf" <<'EOF'
IncludeOptional mods-enabled/*.load
IncludeOptional sites-enabled/*.conf
ProxyRequests On
EOF
printf 'LoadModule proxy_module /usr/lib/apache2/modules/mod_proxy.so\n' > "$D/etc/apache2/mods-enabled/proxy.load"
printf 'LoadModule status_module /usr/lib/apache2/modules/mod_status.so\n' > "$D/etc/apache2/mods-enabled/status.load"
cat > "$D/etc/apache2/sites-enabled/000-default.conf" <<'EOF'
<VirtualHost *:80>
DocumentRoot /var/www/html
<Directory /var/www/>
Options Indexes FollowSymLinks
AllowOverride None
Require all granted
</Directory>
<Directory /var/www/cgi-bin>
Options ExecCGI
Require all granted
</Directory>
<Directory /var/www/owned>
Options SymLinksIfOwnerMatch
Require all granted
</Directory>
<Location /server-status>
SetHandler server-status
Require all granted
</Location>
</VirtualHost>
EOF
run "$D" "$W/out"
has '--WARN-- [apa004w] /var/www/ directory configuration permits symlink following' "$W/out" &&
has '--WARN-- [apa005w] /var/www/cgi-bin directory can hold executable CGI' "$W/out" &&
has '--WARN-- [apa006w] /var/www/ directory will provide content listing' "$W/out" &&
has '--INFO-- [apa003i]' "$W/out" &&
has '--WARN-- [apa008w] ProxyRequests is On' "$W/out" &&
has '--WARN-- [apa010w] server-status is world-readable (<Location /server-status>' "$W/out" &&
has '--INFO-- [apa007i] Apache is configured to load 2 modules.' "$W/out" &&
has 'proxy, status' "$W/out" &&
! grep -q 'apa001w' "$W/out" &&
! grep -q 'apa002w' "$W/out" &&
  ok "Debian full: options, proxy, status, inventory; no Listen, no / verdict" || { bad "debian"; cat "$W/out"; }

V=$W/dav; mkdir -p "$V/etc/apache2/conf-enabled"
printf 'IncludeOptional conf-enabled/*.conf\n' > "$V/etc/apache2/apache2.conf"
cat > "$V/etc/apache2/conf-enabled/dav.conf" <<'EOF'
LoadModule dav_module /usr/lib/apache2/modules/mod_dav.so
<Directory /var/www/dav>
Dav On
Require all granted
</Directory>
EOF
run "$V" "$W/out"
has '--WARN-- [apa009w] WebDAV writes are on for <Directory /var/www/dav>' "$W/out" &&
has 'configured to load 1 module.' "$W/out" &&
  ok "WebDAV directory: apa009w naming the scope" || { bad "dav"; cat "$W/out"; }

H=$W/hard; mkdir -p "$H/etc/apache2"
cat > "$H/etc/apache2/apache2.conf" <<'EOF'
<Directory />
Options FollowSymLinks
AllowOverride None
Require all denied
</Directory>
<Directory /var/www>
Options None
Require all granted
</Directory>
<Location /server-status>
SetHandler server-status
Require ip 127.0.0.1
</Location>
EOF
run "$H" "$W/out"
! grep -q 'apa002w' "$W/out" &&
! grep -q 'apa004w' "$W/out" &&
! grep -q 'apa010w' "$W/out" &&
has 'no LoadModule lines' "$W/out" &&
  ok "hardened: denied /, localhost status, nothing said but inventory" || { bad "hardened"; cat "$W/out"; }

L=$W/legacy; mkdir -p "$L/etc/apache2"
cat > "$L/etc/apache2/apache2.conf" <<'EOF'
<Directory />
Order Allow,Deny
Deny from all
Options None
</Directory>
<Location /server-info>
SetHandler server-info
Allow from all
</Location>
EOF
run "$L" "$W/out"
! grep -q 'apa002w' "$W/out" &&
has '--WARN-- [apa010w] server-info is world-readable' "$W/out" &&
  ok "2.2 closed / is silent; Allow-from-all server-info warns" || { bad "legacy"; cat "$W/out"; }

O=$W/openroot; mkdir -p "$O/etc/apache2"
cat > "$O/etc/apache2/apache2.conf" <<'EOF'
<Directory />
Order Deny,Allow
</Directory>
EOF
run "$O" "$W/out"
[ "`grep -c 'apa002w' \"$W/out\"`" = 2 ] &&
  ok "open / block: access and Options findings" || { bad "openroot"; cat "$W/out"; }

R=$W/rhel; mkdir -p "$R/etc/httpd/conf/conf.modules.d"
cat > "$R/etc/httpd/conf/httpd.conf" <<'EOF'
Listen 80
LoadModule mpm_event_module /usr/lib64/httpd/modules/mod_mpm_event.so
IncludeOptional conf.modules.d/*.conf
EOF
printf 'LoadModule authz_core_module /usr/lib64/httpd/modules/mod_authz_core.so\n' > "$R/etc/httpd/conf/conf.modules.d/00-base.conf"
run "$R" "$W/out"
has '--WARN-- [apa001w] Listen 80 in /etc/httpd/conf/httpd.conf line 1 serves every address' "$W/out" &&
has 'authz_core, mpm_event' "$W/out" &&
  ok "RHEL bare Listen: apa001w; modules sorted" || { bad "rhel"; cat "$W/out"; }

B=$W/rhelbound; mkdir -p "$B/etc/httpd/conf"
printf 'Listen 192.0.2.10:80\n' > "$B/etc/httpd/conf/httpd.conf"
run "$B" "$W/out"
has '--INFO-- [apa001w] Apache listens only on 192.0.2.10:80.' "$W/out" &&
  ok "bound Listen: apa001w INFO" || { bad "rhelbound"; cat "$W/out"; }

E=$W/empty; mkdir -p "$E/etc"
run "$E" "$W/out"
[ -s "$W/out" ] && { bad "empty"; cat "$W/out"; } ||
  ok "no Apache: nothing said"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
