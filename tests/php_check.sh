#!/bin/sh
#
# tests/php_check.sh - check_php on offline roots
#
# Four roots: a loose php.ini (remote includes, version exposed,
# errors shown); a hardened one (off everywhere, errors to stderr);
# two SAPIs with only one gone loose; and an empty root, where PHP
# is not in use and nothing is said. INFO findings only show with
# Tigris_Show_INFO_Msgs=Y. Runs as a user and as root; the fixtures
# read the same for both.
#
TIGER=${TIGER:-`cd "\`dirname \"$0\"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
cp "$W/tigris.conf.base" "$W/tigris.conf" 2>/dev/null || cp "$W/tigris.conf" "$W/tigris.conf.base"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run() {  # run ROOT OUTFILE: check_php with ROOT as the audited system
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/Linux/2/check_php ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }

L=$W/loose; mkdir -p "$L/etc/php/8.2/cli"
cat > "$L/etc/php/8.2/cli/php.ini" <<'EOF'
; a development php.ini
allow_url_include = On
expose_php = On
display_errors = On
EOF
run "$L" "$W/out"
has '--WARN-- [php001w]' "$W/out" &&
has '--INFO-- [php002i]' "$W/out" &&
has '--INFO-- [php003i]' "$W/out" &&
  ok "a loose php.ini: all three" || { bad "loose"; cat "$W/out"; }

H=$W/hard; mkdir -p "$H/etc"
cat > "$H/etc/php.ini" <<'EOF'
allow_url_include = Off
expose_php = 0
display_errors = stderr
log_errors = On
EOF
run "$H" "$W/out"
grep -q 'php001w\|php002i\|php003i' "$W/out" && { bad "hard"; cat "$W/out"; } ||
  ok "hardened (off, 0, stderr): nothing"

S=$W/sapis; mkdir -p "$S/etc/php/8.2/cli" "$S/etc/php/8.2/fpm"
cat > "$S/etc/php/8.2/cli/php.ini" <<'EOF'
allow_url_include = Off
expose_php = Off
display_errors = Off
EOF
cat > "$S/etc/php/8.2/fpm/php.ini" <<'EOF'
allow_url_include = On
expose_php = Off
display_errors = Off
EOF
run "$S" "$W/out"
has '--WARN-- [php001w]' "$W/out" &&
grep -q 'fpm/php.ini' "$W/out" && ! grep -q 'cli/php.ini' "$W/out" &&
  ok "two SAPIs, one loose: names only the loose one" || { bad "sapis"; cat "$W/out"; }

E=$W/empty; mkdir -p "$E/etc"
run "$E" "$W/out"
[ -s "$W/out" ] && { bad "empty"; cat "$W/out"; } ||
  ok "no php.ini: nothing said"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
