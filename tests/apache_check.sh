#!/bin/sh
#
# tests/apache_check.sh - check_apache on offline roots
#
# A Debian layout with everything on (symlinks, CGI, listings, an
# open proxy, an open status page); a WebDAV directory; a hardened
# host (Require-denied /, localhost-only status); a 2.2 host with /
# properly closed and server-info allowed to all; an open / block; a
# RHEL host listening bare (Includes from ServerRoot) and one bound;
# FreeBSD's default ServerRoot; what the reader must take as the
# server does (case, quotes, continuations, forged markers); an
# Include ring and a configuration past the file limit; and an empty
# root, where nothing is said. INFO findings only show with
# Tigris_Show_INFO_Msgs=Y. Runs as a user and as root; the fixtures
# read the same for both.
#
TIGER=${TIGER:-`cd "\`dirname \"$0\"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
cp "$W/tigris.conf" "$W/tigris.conf.base"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run() {  # run ROOT OUTFILE: check_apache with ROOT as the audited system
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
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

# RHEL's layout: relative Includes are ServerRoot's (/etc/httpd), not
# the directory httpd.conf is in
R=$W/rhel; mkdir -p "$R/etc/httpd/conf" "$R/etc/httpd/conf.modules.d" "$R/etc/httpd/conf.d"
cat > "$R/etc/httpd/conf/httpd.conf" <<'EOF'
ServerRoot "/etc/httpd"
Listen 80
LoadModule mpm_event_module /usr/lib64/httpd/modules/mod_mpm_event.so
Include conf.modules.d/*.conf
IncludeOptional conf.d/*.conf
EOF
printf 'LoadModule authz_core_module /usr/lib64/httpd/modules/mod_authz_core.so\n' > "$R/etc/httpd/conf.modules.d/00-base.conf"
cat > "$R/etc/httpd/conf.d/autoindex.conf" <<'EOF'
<Directory "/usr/share/httpd/icons">
    Options Indexes MultiViews FollowSymlinks
    Require all granted
</Directory>
EOF
run "$R" "$W/out"
has '--WARN-- [apa001w] Listen 80 in /etc/httpd/conf/httpd.conf line 2 serves every address' "$W/out" &&
has 'authz_core, mpm_event' "$W/out" &&
has '--WARN-- [apa006w] /usr/share/httpd/icons directory will provide content listing' "$W/out" &&
  ok "RHEL: conf.modules.d and conf.d read from ServerRoot; bare Listen" || { bad "rhel"; cat "$W/out"; }

# with no ServerRoot line the platform's default holds: /usr/local on
# FreeBSD, whose Includes are etc/apache24/...
F=$W/freebsd; mkdir -p "$F/etc" "$F/usr/local/etc/apache24/modules.d" "$F/usr/local/etc/apache24/Includes"
cat > "$F/usr/local/etc/apache24/httpd.conf" <<'EOF'
LoadModule authz_core_module libexec/apache24/mod_authz_core.so
Include etc/apache24/modules.d/[0-9][0-9][0-9]_*.conf
Include etc/apache24/Includes/*.conf
EOF
printf 'LoadModule php_module libexec/apache24/libphp.so\n' > "$F/usr/local/etc/apache24/modules.d/080_mod_php.conf"
printf 'LoadModule nope_module x.so\n' > "$F/usr/local/etc/apache24/modules.d/README_modules.d"
printf '<Directory /usr/local/www/site>\nOptions Indexes\nRequire all granted\n</Directory>\n' > "$F/usr/local/etc/apache24/Includes/site.conf"
run "$F" "$W/out"
has 'configured to load 2 modules.' "$W/out" && has 'authz_core, php' "$W/out" &&
has '--WARN-- [apa006w] /usr/local/www/site directory' "$W/out" &&
  ok "FreeBSD: default ServerRoot /usr/local, bracket globs" || { bad "freebsd"; cat "$W/out"; }

# what the reader takes as the server does: directive names in any
# case, quoted paths, CRLF, a backslash continuing a line (the line
# numbers stay the file's); the old marker text and a forged control
# byte in the configuration move nothing; "Include" inside another
# directive's argument is not an Include
P=$W/parse; mkdir -p "$P/etc/apache2/conf.d"
{
  printf '<Directory /var/www/a>\n# @@FILE@@ /etc/apache2/elsewhere.conf 500\n\001F 700 /etc/apache2/forged.conf\n'
  printf 'Options Indexes \\\n        FollowSymLinks ExecCGI\nRequire all granted\n</Directory>\n'
  printf 'include conf.d/mods.conf\nINCLUDEOPTIONAL "conf.d/q*.conf"\n'
  printf '<Location /x>\nHeader set X-Note "Include all"\n</Location>\n'
  printf '<Directory /var/www/b>\nOptions Indexes\nRequire all granted\n</Directory>\n'
} > "$P/etc/apache2/apache2.conf"
printf 'LoadModule status_module x.so\n' > "$P/etc/apache2/conf.d/mods.conf"
printf 'LoadModule quoted_module x.so\r\n' > "$P/etc/apache2/conf.d/quoted.conf"
run "$P" "$W/out"
has '[apa004w] /var/www/a directory configuration permits symlink following (/etc/apache2/apache2.conf line 4)' "$W/out" &&
has '[apa005w] /var/www/a directory can hold executable CGI (/etc/apache2/apache2.conf line 4)' "$W/out" &&
has '[apa006w] /var/www/b directory will provide content listing if there are no index.html files (/etc/apache2/apache2.conf line 14)' "$W/out" &&
has 'quoted, status' "$W/out" &&
! grep -q 'elsewhere\|forged' "$W/out" &&
  ok "reader: case, quotes, CRLF, continuation, no forged positions" || { bad "parse"; cat "$W/out"; }

# a wildcard in a directory part, and a directory named by Include:
# what is in it and below, dotfiles left out, as the server reads it
X=$W/wild; mkdir -p "$X/etc/apache2/vh/one" "$X/etc/apache2/vh/two" "$X/etc/apache2/dir/sub"
printf 'Include /etc/apache2/vh/*/site.conf\nInclude dir\n' > "$X/etc/apache2/apache2.conf"
printf 'LoadModule one_module x.so\n' > "$X/etc/apache2/vh/one/site.conf"
printf 'LoadModule two_module x.so\n' > "$X/etc/apache2/vh/two/site.conf"
printf 'LoadModule d1_module x.so\n' > "$X/etc/apache2/dir/a.conf"
printf 'LoadModule d2_module x.so\n' > "$X/etc/apache2/dir/sub/b.conf"
printf 'LoadModule hidden_module x.so\n' > "$X/etc/apache2/dir/.hidden.conf"
run "$X" "$W/out"
has 'configured to load 4 modules.' "$W/out" && has 'd1, d2, one, two' "$W/out" &&
  ok "wildcard directory part, directory Include" || { bad "wild"; cat "$W/out"; }

# a <DirectoryMatch> (any *Match block) ends at its closing tag:
# what follows is not judged as inside it
Q=$W/match; mkdir -p "$Q/etc/apache2"
cat > "$Q/etc/apache2/apache2.conf" <<'EOF'
<DirectoryMatch "^/srv/www/[^/]+/public">
Require all granted
</DirectoryMatch>
<VirtualHost *:80>
Options Indexes
<Location /dav>
Dav On
Require all granted
</Location>
</VirtualHost>
EOF
run "$Q" "$W/out"
! grep -q 'apa006w' "$W/out" &&
has '[apa009w] WebDAV writes are on for <Location /dav>' "$W/out" &&
  ok "*Match blocks close: nothing after them judged inside" || { bad "match"; cat "$W/out"; }

# a ring of Includes (each file includes them all) is read once round,
# not 3^16 times, and a configuration naming more than 400 files is
# read that far and said to be read in part
G=$W/ring; mkdir -p "$G/etc/apache2/conf.d"
printf 'IncludeOptional conf.d/*.conf\nInclude apache2.conf\n' > "$G/etc/apache2/apache2.conf"
for f in a b c; do printf 'IncludeOptional /etc/apache2/conf.d/*.conf\nLoadModule %s_module x.so\n' $f > "$G/etc/apache2/conf.d/$f.conf"; done
run "$G" "$W/out"
has 'configured to load 3 modules.' "$W/out" && ! grep -q 'apa011i' "$W/out" &&
  ok "Include ring: each file read once per chain, finishes" || { bad "ring"; cat "$W/out"; }
M=$W/many; mkdir -p "$M/etc/apache2/sites-enabled"
printf 'IncludeOptional sites-enabled/*.conf\n' > "$M/etc/apache2/apache2.conf"
i=0; while [ $i -lt 405 ]; do printf '<VirtualHost *:80>\n</VirtualHost>\n' > "$M/etc/apache2/sites-enabled/s$i.conf"; i=`expr $i + 1`; done
run "$M" "$W/out"
[ "`grep -c 'apa011i' \"$W/out\"`" = 1 ] && has 'Includes stop being followed after 400 files' "$W/out" &&
  ok "over 400 files: read in part, said once" || { bad "many"; cat "$W/out"; }

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
