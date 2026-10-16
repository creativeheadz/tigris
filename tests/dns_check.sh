#!/bin/sh
#
# tests/dns_check.sh - check_dns against a root of its own
#
# A fake root with a resolv.conf holding four servers and a bad line,
# a hosts file duplicating a line (dns007w), an unbound opening
# recursion from an included file, and a bind opening
# it through a named ACL. Then roots with no usable nameserver, a single
# real one, a lone loopback stub (fine), an authoritative-only bind
# (recursion no: not analyzed), clean daemon configurations, a PowerDNS
# recursor open through an include-dir with an open authoritative
# server beside it, and a PowerDNS pair closed to their own networks.
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
run() {  # run ROOT OUTFILE: check_dns against ROOT
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { echo "Tigris_Sysctl_Root='$1'"; echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_dns ) 2>&1 | join > "$2"
}

r="$W/root"
mkdir -p "$r/etc" "$r/etc/unbound/unbound.conf.d" "$r/etc/bind"
printf 'nameserver 192.0.2.1\nnameserver 192.0.2.2\nnameserver 192.0.2.3\nnameserver 192.0.2.4\nnameserver not-an-address\n' > "$r/etc/resolv.conf"
printf 'server:\n  interface: 127.0.0.1\ninclude: /etc/unbound/unbound.conf.d/*.conf\n' > "$r/etc/unbound/unbound.conf"
printf 'server:\n  access-control: 127.0.0.0/8 allow\n  access-control: 0.0.0.0/0 allow\n' > "$r/etc/unbound/unbound.conf.d/open.conf"
printf '127.0.0.1 localhost\n192.0.2.10 db.example\n192.0.2.10 db.example # appended twice\n' > "$r/etc/hosts"
printf 'include "/etc/bind/named.conf.options";\n' > "$r/etc/bind/named.conf"
printf 'acl "open" { any; };\noptions {\n  allow-recursion { open; };\n  allow-recursion { any; };\n};\n' > "$r/etc/bind/named.conf.options"
run "$r" "$W/out"
has()   { grep -F -q -- "$1" "$W/out"; }

has "[dns002w] 4 nameservers in /etc/resolv.conf, but only the first 3 are used; 192.0.2.4 ignored." &&
  ok "four servers: dns002w names the ignored one" || { bad "four"; cat "$W/out"; }
has "[dns003w] Line 5 of /etc/resolv.conf names 'not-an-address' as a nameserver, which is not an IP address; it is ignored." &&
  ok "a bad line: dns003w with its line number" || { bad "bad line"; cat "$W/out"; }
has "[dns005f] \`/etc/unbound/unbound.conf.d/open.conf' lets anyone use this resolver (access-control: 0.0.0.0/0 allow):" &&
  ok "unbound open through an included file: dns005f" || { bad "unbound"; cat "$W/out"; }
has "[dns006f] \`/etc/bind/named.conf.options' lets anyone recurse: allow-recursion names 'open', an ACL holding 'any'." &&
  has "[dns006f] \`/etc/bind/named.conf.options' lets anyone recurse: allow-recursion holds 'any'." &&
  ok "bind open through a named ACL and directly: dns006f" || { bad "bind"; cat "$W/out"; }
has "[dns007w] Duplicate line in /etc/hosts: '192.0.2.10 db.example'." &&
  ok "a duplicated hosts line, comments aside: dns007w" || { bad "hosts"; cat "$W/out"; }
grep -q "$r" "$W/out" && bad "a finding names where the root is on this host" || ok "findings name the root's own paths"

# no usable nameserver: none at all, then all invalid
N=$W/none
mkdir -p "$N/etc"
printf '# empty\n' > "$N/etc/resolv.conf"
run "$N" "$W/none.out"
grep -F -q '[dns001f] No usable nameserver in /etc/resolv.conf: names cannot be resolved.' "$W/none.out" &&
  ok "no nameserver lines: dns001f" || { bad "none"; cat "$W/none.out"; }
B=$W/badonly
mkdir -p "$B/etc"
printf 'nameserver 0.0.0.0\nnameserver 999.1.1.1\n' > "$B/etc/resolv.conf"
run "$B" "$W/bad.out"
grep -F -q '[dns001f] No usable nameserver in /etc/resolv.conf: names cannot be resolved.' "$W/bad.out" &&
  grep -F -q "[dns003w] Line 1 of /etc/resolv.conf names '0.0.0.0'" "$W/bad.out" &&
  grep -F -q "[dns003w] Line 2 of /etc/resolv.conf names '999.1.1.1'" "$W/bad.out" &&
  ok "all invalid: dns001f, and each line its dns003w" || { bad "bad only"; cat "$W/bad.out"; }

# one server: a real one is noted, a loopback stub is not
S=$W/single
mkdir -p "$S/etc"
printf 'nameserver 192.0.2.53\n' > "$S/etc/resolv.conf"
run "$S" "$W/single.out"
grep -F -q '[dns004i] A single nameserver (192.0.2.53) in /etc/resolv.conf: no fallback if it stops answering.' "$W/single.out" &&
  ok "a single real nameserver: dns004i" || { bad "single"; cat "$W/single.out"; }
L=$W/stub
mkdir -p "$L/etc"
printf 'nameserver 127.0.0.53\noptions edns0 trust-ad\n' > "$L/etc/resolv.conf"
run "$L" "$W/stub.out"
grep -q 'dns00[124]' "$W/stub.out" && { bad "stub"; cat "$W/stub.out"; } || ok "a lone loopback stub: nothing"

# bind authoritative-only, and clean daemons: nothing
A=$W/auth
mkdir -p "$A/etc" "$A/etc/bind"
printf 'nameserver 192.0.2.1\nnameserver 192.0.2.2\n' > "$A/etc/resolv.conf"
printf 'options {\n  recursion no;\n  allow-recursion { any; };\n};\n' > "$A/etc/bind/named.conf"
run "$A" "$W/auth.out"
grep -q 'dns00[156]' "$W/auth.out" && { bad "authoritative"; cat "$W/auth.out"; } || ok "recursion no: the dead allow-recursion is not reported"
C=$W/clean
mkdir -p "$C/etc" "$C/etc/unbound" "$C/etc/bind"
printf 'nameserver 192.0.2.1\nnameserver 192.0.2.2\n' > "$C/etc/resolv.conf"
printf 'server:\n  access-control: 127.0.0.0/8 allow\n  access-control: 10.0.0.0/8 allow\n' > "$C/etc/unbound/unbound.conf"
printf 'options {\n  allow-recursion { localhost; localnets; };\n};\n' > "$C/etc/bind/named.conf"
run "$C" "$W/clean.out"
grep -q 'dns00[1-6]' "$W/clean.out" && { bad "clean"; cat "$W/clean.out"; } || ok "closed daemons and two servers: nothing"

# PowerDNS: an open recursor and an open authoritative server, then a pair closed to their own networks
P=$W/pdns
mkdir -p "$P/etc" "$P/etc/powerdns/recursor.conf.d"
printf 'nameserver 192.0.2.1\nnameserver 192.0.2.2\n' > "$P/etc/resolv.conf"
printf 'allow-from=127.0.0.0/8, 10.0.0.0/8\ninclude-dir=/etc/powerdns/recursor.conf.d\n' > "$P/etc/powerdns/recursor.conf"
printf '# opened by hand\nallow-from=127.0.0.1, 0.0.0.0/0\n' > "$P/etc/powerdns/recursor.conf.d/open.conf"
printf 'allow-recursion=::/0\n' > "$P/etc/powerdns/pdns.conf"
run "$P" "$W/pdns.out"
grep -F -q "[dns008f] \`/etc/powerdns/recursor.conf.d/open.conf' lets anyone use this recursor (allow-from holds the whole Internet)" "$W/pdns.out" &&
grep -F -q "[dns008f] \`/etc/powerdns/pdns.conf' lets anyone recurse (allow-recursion holds the whole Internet)" "$W/pdns.out" &&
  ok "PowerDNS open through include-dir, auth open directly: dns008f" || { bad "pdns"; cat "$W/pdns.out"; }
D=$W/pdnsclosed
mkdir -p "$D/etc" "$D/etc/powerdns"
printf 'nameserver 192.0.2.1\nnameserver 192.0.2.2\n' > "$D/etc/resolv.conf"
printf 'allow-from=127.0.0.0/8, 10.0.0.0/8\n' > "$D/etc/powerdns/recursor.conf"
printf '# defaults: localhost and the private networks\n' > "$D/etc/powerdns/pdns.conf"
run "$D" "$W/pdnsclosed.out"
grep -q 'dns008f' "$W/pdnsclosed.out" && { bad "pdnsclosed"; cat "$W/pdnsclosed.out"; } || ok "PowerDNS closed and defaulted: nothing"

# an offline root (TIGRIS_ROOT, as tigris --root sets it)
R=$W/img
mkdir -p "$R/etc"
printf 'nameserver 192.0.2.9\n' > "$R/etc/resolv.conf"
cp "$W/tigris.conf.base" "$W/tigris.conf"; echo "Tigris_Show_INFO_Msgs=Y" >> "$W/tigris.conf"
( cd "$W" && TIGRIS_ROOT=$R TIGERHOMEDIR=$W sh ./systems/Linux/2/check_dns ) 2>&1 | join > "$W/off"
grep -F -q '[dns004i] A single nameserver (192.0.2.9)' "$W/off" &&
  ok "offline root: the single nameserver" || { bad "offline"; cat "$W/off"; }
grep -q "$R" "$W/off" && bad "offline root: a finding names where the root is on this host" || ok "offline root: findings name the root's own paths"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
