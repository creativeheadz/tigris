#!/bin/sh
#
# tests/passwd_sunos_check.sh - SunOS check_passwd on offline roots
#
# Three legs: a loose root (a second uid 0, a doubled name and uid,
# root a plain user instead of a role); a tight root (root alone at
# uid 0, root a role); and a root with no user_attr at all, where
# there is nothing to say about roles. Runs as a user and as root;
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
run() {  # run ROOT OUTFILE: check_passwd with ROOT as the audited system
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/SunOS/default/check_passwd ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }
empty() { [ ! -s "$1" ]; }

B=$W/bad; mkdir -p "$B/etc"
cat > "$B/etc/passwd" <<'EOF'
root:x:0:0:Super-User:/root:/bin/bash
daemon:x:1:1::/:
evil:x:0:0::/:/bin/bash
ops:x:100:100::/home/ops:/bin/bash
ops:x:100:100::/home/ops2:/bin/bash
nobody:x:60001:60001::/:
EOF
cat > "$B/etc/shadow" <<'EOF'
root:$5$rounds=5000$xx:18000::::::
daemon:*:18000::::::
evil:::::::::
ops:*:18000::::::
nobody:*:18000::::::
EOF
cat > "$B/etc/user_attr" <<'EOF'
root::::
daemon::::
EOF
run "$B" "$W/out"
has '--WARN-- [pass017w]' "$W/out" &&
has 'evil' "$W/out" &&
has '--WARN-- [pass001w]' "$W/out" &&
has '--WARN-- [pass002w]' "$W/out" &&
has '--WARN-- [rol001w]' "$W/out" &&
  ok "uid 0, doubled name and uid, root no role: all four" || { bad "bad"; cat "$W/out"; }

T=$W/tight; mkdir -p "$T/etc" "$T/etc/default"
cat > "$T/etc/passwd" <<'EOF'
root:x:0:0:Super-User:/root:/bin/bash
daemon:x:1:1::/:
ops:x:100:100::/home/ops:/bin/bash
nobody:x:60001:60001::/:
EOF
: > "$T/etc/shadow"
cat > "$T/etc/user_attr" <<'EOF'
root::::type=role
daemon::::
ops::::type=normal
EOF
cat > "$T/etc/default/passwd" <<'EOF'
MAXWEEKS=13
MINWEEKS=1
PASSLENGTH=14
EOF
run "$T" "$W/out"
empty "$W/out" &&
  ok "root alone at uid 0, root a role, policy set: silent" || { bad "tight noisy"; cat "$W/out"; }

P=$W/weakpol; mkdir -p "$P/etc" "$P/etc/default"
cp "$T/etc/passwd" "$P/etc/passwd"
cp "$T/etc/user_attr" "$P/etc/user_attr"
cat > "$P/etc/default/passwd" <<'EOF'
# MAXWEEKS is commented out: passwords never expire
#MAXWEEKS=13
PASSLENGTH=6  # short enough to guess
EOF
run "$P" "$W/out"
has '--WARN-- [pwp001w]' "$W/out" &&
has '--WARN-- [pwp002w]' "$W/out" &&
  ok "no aging, short passwords: pwp001w, pwp002w" || { bad "weakpol"; cat "$W/out"; }

E=$W/norole; mkdir -p "$E/etc"
cp "$T/etc/passwd" "$E/etc/passwd"
run "$E" "$W/out"
empty "$W/out" &&
  ok "no user_attr: nothing to say about roles" || { bad "norole noisy"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
