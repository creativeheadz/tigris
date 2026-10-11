#!/bin/sh
#
# tests/ldap_check.sh - check_ldap on offline roots
#
# Five roots: a Debian-layout server with a world-readable rootpw and
# no TLS, plus a client bindpw left readable (all three findings); the
# same files locked down to root (nothing); a server with a
# certificate configured (no ldap002w); a Red Hat-layout cn=config
# tree with a readable olcRootPW and no TLS; and an empty root, where
# LDAP is not in use and nothing is said. Runs as a user and as root;
# the fixtures read the same for both.
#
TIGER=${TIGER:-`cd "\`dirname \"$0\"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run() {  # run ROOT OUTFILE: check_ldap with ROOT as the audited system
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/Linux/2/check_ldap ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }

B=$W/bad; mkdir -p "$B/etc/ldap"
cat > "$B/etc/ldap/slapd.conf" <<'EOF'
include /etc/ldap/schema/core.schema
rootdn "cn=admin,dc=example,dc=com"
rootpw {SSHA}xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
EOF
chmod 644 "$B/etc/ldap/slapd.conf"
printf 'base dc=example,dc=com\nbinddn cn=proxy,dc=example,dc=com\nbindpw secret123\n' > "$B/etc/ldap.conf"
chmod 644 "$B/etc/ldap.conf"
run "$B" "$W/out"
has "--WARN-- [ldap001w] \`/etc/ldap/slapd.conf' holds the LDAP directory manager password" "$W/out" &&
has "--WARN-- [ldap001w] \`/etc/ldap.conf' holds the LDAP bind password in clear" "$W/out" &&
has '--WARN-- [ldap002w] The directory takes binds with no TLS configured' "$W/out" &&
  ok "readable rootpw, readable bindpw, no TLS: all three" || { bad "bad"; cat "$W/out"; }

G=$W/good; mkdir -p "$G/etc/ldap"
cp "$B/etc/ldap/slapd.conf" "$G/etc/ldap/slapd.conf"
cp "$B/etc/ldap.conf" "$G/etc/ldap.conf"
chmod 600 "$G/etc/ldap/slapd.conf" "$G/etc/ldap.conf"
run "$G" "$W/out"
grep -q 'ldap001w' "$W/out" && { bad "good-creds"; cat "$W/out"; } ||
has '--WARN-- [ldap002w]' "$W/out" &&
  ok "locked-down credentials, still no TLS: only ldap002w" || { bad "good"; cat "$W/out"; }

T=$W/tls; mkdir -p "$T/etc/openldap"
cat > "$T/etc/openldap/slapd.conf" <<'EOF'
rootdn "cn=Manager,dc=example,dc=com"
rootpw {SSHA}xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TLSCertificateFile /etc/openldap/certs/server.crt
EOF
chmod 644 "$T/etc/openldap/slapd.conf"
run "$T" "$W/out"
has 'ldap001w' "$W/out" && ! grep -q 'ldap002w' "$W/out" &&
  ok "a certificate configured: no ldap002w" || { bad "tls"; cat "$W/out"; }

N=$W/cnconfig; mkdir -p "$N/etc/openldap/slapd.d"
cat > "$N/etc/openldap/slapd.d/cn=config.ldif" <<'EOF'
dn: cn=config
olcRootPW: {SSHA}xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
EOF
chmod 644 "$N/etc/openldap/slapd.d/cn=config.ldif"
run "$N" "$W/out"
has "--WARN-- [ldap001w] \`/etc/openldap/slapd.d/cn=config.ldif' holds the LDAP directory manager password" "$W/out" &&
has '--WARN-- [ldap002w]' "$W/out" &&
  ok "cn=config with a readable olcRootPW, no TLS: both" || { bad "cnconfig"; cat "$W/out"; }

E=$W/empty; mkdir -p "$E/etc"
run "$E" "$W/out"
[ -s "$W/out" ] && { bad "empty"; cat "$W/out"; } ||
  ok "no LDAP config files: nothing said"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
