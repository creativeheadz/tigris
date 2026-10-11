#!/bin/sh
#
# tests/logfiles_bsd_check.sh - FreeBSD check_logfiles on offline roots
#
# Three legs: a loose root (a writable newsyslog.conf, a missing
# managed log, a writable messages file, a loose mode column);
# a tight root (locked config, present 644 logs, tight modes,
# a null-pointed log); and no newsyslog.conf at all, where there
# is nothing to manage and nothing is said. Runs as a user and
# as root; the fixtures read the same for both.
#
TIGER=${TIGER:-`cd "\`dirname \"$0\"\`/.." && pwd`}
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
umask 022
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run() {  # run ROOT OUTFILE: check_logfiles with ROOT as the audited system
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/FreeBSD/default/check_logfiles ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }
empty() { [ ! -s "$1" ]; }

B=$W/bad
mkdir -p "$B/etc" "$B/var/log"
cat > "$B/etc/newsyslog.conf" <<'EOF'
# logfile [owner:group] mode count size when flags
/var/log/messages 644 7 * @T00 -
/var/log/maillog 666 7 * @T00 -
/var/log/gone root:wheel 644 7 * @T00 -
EOF
chmod 666 "$B/etc/newsyslog.conf"
touch "$B/var/log/messages" "$B/var/log/maillog"
chmod 666 "$B/var/log/messages"
chmod 644 "$B/var/log/maillog"
run "$B" "$W/out"
has '--FAIL-- [logf005f]' "$W/out" &&
has 'newsyslog.conf' "$W/out" &&
has '--FAIL-- [logf001f]' "$W/out" &&
has '/var/log/gone' "$W/out" &&
has '--WARN-- [logf010w]' "$W/out" &&
has 'maillog' "$W/out" &&
  ok "writable conf, missing log, writable log, loose mode: all four" || { bad "bad"; cat "$W/out"; }

T=$W/tight
mkdir -p "$T/etc" "$T/var/log"
cat > "$T/etc/newsyslog.conf" <<'EOF'
/var/log/messages 644 7 * @T00 -
/var/log/none root:wheel 644 7 * @T00 -
EOF
chmod 644 "$T/etc/newsyslog.conf"
touch "$T/var/log/messages"
chmod 644 "$T/var/log/messages"
# a log pointed at null: the root has no /dev of its own (a running system
# mounts one), and this host's is never read in its place
ln -s /dev/null "$T/var/log/none"
run "$T" "$W/out"
empty "$W/out" &&
  ok "locked config, present logs, null sink: silent" || { bad "tight noisy"; cat "$W/out"; }

E=$W/emptyroot; mkdir -p "$E/etc"
run "$E" "$W/out"
empty "$W/out" &&
  ok "no newsyslog.conf: silent" || { bad "empty noisy"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
