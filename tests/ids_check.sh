#!/bin/sh
#
# tests/ids_check.sh - check_ids on offline roots
#
# Six roots: fail2ban with nothing enabled; fail2ban watching
# (one jail on); Snort with its rule includes commented out;
# Suricata with rules; an OSSEC config; and an empty root, where
# no watcher is configured and nothing is said. INFO findings only
# show with Tigris_Show_INFO_Msgs=Y. Runs as a user and as root; the
# fixtures read the same for both.
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
run() {  # run ROOT OUTFILE: check_ids with ROOT as the audited system
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/Linux/2/check_ids ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }

B=$W/blind; mkdir -p "$B/etc/fail2ban"
cat > "$B/etc/fail2ban/jail.local" <<'EOF'
[DEFAULT]
bantime = 1h
[sshd]
enabled = false
EOF
run "$B" "$W/out"
has '--WARN-- [ids001w]' "$W/out" &&
has '--INFO-- [ids003i]' "$W/out" &&
  ok "fail2ban with nothing enabled: ids001w plus inventory" || { bad "blind"; cat "$W/out"; }

A=$W/active; mkdir -p "$A/etc/fail2ban/jail.d"
cat > "$A/etc/fail2ban/jail.d/sshd.conf" <<'EOF'
[sshd]
enabled = true
bantime = 1h
EOF
run "$A" "$W/out"
has '--INFO-- [ids003i]' "$W/out" &&
! grep -q 'ids001w' "$W/out" &&
  ok "one jail on, via a drop-in: only inventory" || { bad "active"; cat "$W/out"; }

S=$W/snort; mkdir -p "$S/etc/snort"
cat > "$S/etc/snort/snort.conf" <<'EOF'
# no rules on this sensor yet
# include $RULE_PATH/local.rules
include classification.config
EOF
run "$S" "$W/out"
has '--WARN-- [ids002w] Snort is configured but loads no rules.' "$W/out" &&
  ok "Snort with no rule includes: ids002w" || { bad "snort"; cat "$W/out"; }

U=$W/suri; mkdir -p "$U/etc/suricata"
cat > "$U/etc/suricata/suricata.yaml" <<'EOF'
default-rule-path: /var/lib/suricata/rules
rule-files:
  - suricata.rules
EOF
run "$U" "$W/out"
has '--INFO-- [ids003i]' "$W/out" &&
! grep -q 'ids002w' "$W/out" &&
  ok "Suricata with rules: only inventory" || { bad "suri"; cat "$W/out"; }

O=$W/ossec; mkdir -p "$O/etc" "$O/var/ossec/etc"
printf '<ossec_config>\n  <rules>\n    <include>rules_config.xml</include>\n  </rules>\n</ossec_config>\n' > "$O/var/ossec/etc/ossec.conf"
run "$O" "$W/out"
has '--INFO-- [ids003i]' "$W/out" &&
! grep -q 'ids001w\|ids002w' "$W/out" &&
  ok "an OSSEC config: only inventory" || { bad "ossec"; cat "$W/out"; }

E=$W/empty; mkdir -p "$E/etc"
run "$E" "$W/out"
[ -s "$W/out" ] && { bad "empty"; cat "$W/out"; } ||
  ok "no watcher configured: nothing said"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
