#!/bin/sh
#
# tests/firewall_check.sh - check_firewall against real rulesets
#
# The fixtures in tests/fixtures/firewall are "nft list ruleset" and
# "iptables -S INPUT" output captured from containers with their own
# network namespace (docker run --cap-add NET_ADMIN): nothing loaded, ufw
# enabled on Ubuntu 24.04, firewalld started on Fedora, and nftables
# configurations loaded with nft 1.1.3 on Debian stable. Each run feeds one
# of them through Tiger_NFT_Cmd and checks what is concluded for IPv4 and
# IPv6. Logging is covered both ways: verdicts with log rules stay
# silent, input without any is fire007w.
#
# The docker-* fixtures are the rules Docker writes for published ports:
# Hera (Docker 29.8.2, iptables-nft), and docker:dind containers (29.8.2
# with its iptables and its nftables backend, 27.5.1) publishing TCP and
# UDP ports on every address, one on loopback and one on the container's
# own address, and one on an IPv6 network, then ufw enabled beside them.
# The *.ipt files are the same rules as "iptables -S" prints them, which
# is what a host without nft (Ubuntu) gives.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
FX="$TIGER/tests/fixtures/firewall"
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# A /proc and /sys of our own: IPv6 on, no legacy iptables tables
mkdir -p "$W/sys/proc/net" "$W/sys/proc/sys/net/ipv6/conf/all" "$W/sys/sys/module/nf_tables"
: > "$W/sys/proc/net/if_inet6"
echo 0 > "$W/sys/proc/sys/net/ipv6/conf/all/disable_ipv6"
cp "$W/tigerrc" "$W/tigerrc.base"

# go NFT-COMMAND [setting=value ...]: run the check, findings to $W/out
go() {
  cp "$W/tigerrc.base" "$W/tigerrc"
  {
    echo "Tiger_NFT_Cmd='$1'"
    echo "Tiger_Sysctl_Root='$W/sys'"
    echo "Tiger_Firewall_Frontends=''"
    echo "Tiger_Show_INFO_Msgs=Y"
    shift
    for s; do echo "$s"; done
  } >> "$W/tigerrc"
  ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_firewall ) 2>&1 |
    # one line per finding: join the wrapped lines
    awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
    tr -s ' ' > "$W/out"
}
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -c -- "$1" "$W/out"; }
# expect FIXTURE "v4 text" "v6 text" what: each text is what must appear
expect() {
  go "cat $FX/$1"
  if has "$2" && has "$3"; then ok "$4"; else bad "$4"; sed 's/^/     /' "$W/out"; fi
}

expect none.nft \
  '--WARN-- [fire001w] Incoming IPv4 traffic is not denied by default: no input chain drops what it does not accept. No chain on the input hook filters IPv4' \
  '--WARN-- [fire002w] Incoming IPv6 traffic is not denied by default' \
  "nothing loaded: WARN for IPv4 and IPv6"
expect ufw.nft \
  '--INFO-- [fire003i] Incoming IPv4 traffic is denied by default (nftables ip filter INPUT: policy drop).' \
  '--INFO-- [fire003i] Incoming IPv6 traffic is denied by default (nftables ip6 filter INPUT: policy drop).' \
  "ufw enabled (Ubuntu 24.04, iptables-nft): denied for both"
expect firewalld.nft \
  '--INFO-- [fire003i] Incoming IPv4 traffic is denied by default (nftables inet firewalld filter_INPUT: ends with an unconditional reject).' \
  '--INFO-- [fire003i] Incoming IPv6 traffic is denied by default (nftables inet firewalld filter_INPUT: ends with an unconditional reject).' \
  "firewalld (Fedora): policy accept, but the chain ends with a reject"
expect inet-drop.nft \
  'Incoming IPv4 traffic is denied by default (nftables inet filter input: policy drop).' \
  'Incoming IPv6 traffic is denied by default (nftables inet filter input: policy drop).' \
  "an inet chain with policy drop covers both families"
expect final-drop.nft \
  'IPv4 traffic is denied by default (nftables inet filter input: ends with an unconditional drop).' \
  'IPv6 traffic is denied by default (nftables inet filter input: ends with an unconditional drop).' \
  "a last rule 'counter packets 0 bytes 0 drop' is a default-deny"
expect log-reject.nft \
  'IPv4 traffic is denied by default (nftables ip filter input: ends with an unconditional drop).' \
  'IPv6 traffic is denied by default (nftables ip6 filter input: ends with an unconditional reject).' \
  "log and counter before the verdict, a set in the table, reject with an ICMPv6 type"

# Logging: logged verdicts are silent, unlogged input is fire007w
go "cat $FX/log-reject.nft"
[ "`count fire007w`" = 0 ] && ok "logged drop and reject: no fire007w" || { bad "log-reject logs"; cat "$W/out"; }
go "cat $FX/ufw.nft"
[ "`count fire007w`" = 0 ] && ok "ufw logs its blocks from its own chains: no fire007w" || { bad "ufw logs"; cat "$W/out"; }
go "cat $FX/none.nft"
[ "`count fire007w`" = 2 ] && ok "nothing loaded: fire007w for IPv4 and IPv6" || { bad "unlogged input"; cat "$W/out"; }

expect v4-only.nft \
  'IPv4 traffic is denied by default (nftables ip filter input: policy drop).' \
  '--WARN-- [fire002w] Incoming IPv6 traffic is not denied by default: no input chain drops what it does not accept. No chain on the input hook filters IPv6' \
  "an ip-family chain protects IPv4 only, and IPv6 is reported open"
expect conditional.nft \
  '[fire001w] Incoming IPv4 traffic is not denied by default: no input chain drops what it does not accept. Input chains: nftables inet filter input: policy accept.' \
  '[fire002w] Incoming IPv6 traffic is not denied by default' \
  "drops that only match some traffic are not a default-deny"
expect debian-default.nft \
  'Input chains: nftables inet filter input: policy accept.' \
  '[fire002w]' \
  "Debian's default nftables.conf (chains with no policy) is open"
expect forward-only.nft \
  '[fire001w] Incoming IPv4 traffic is not denied by default' \
  '[fire002w] Incoming IPv6 traffic is not denied by default' \
  "a forward chain with policy drop does not protect the host"

# A stand-in for iptables: fakeipt INPUT NAT USER, then what the check
# asks for; "-" for a chain that does not exist. Every call is logged.
cat > "$W/fakeipt" <<'EOF'
#!/bin/sh
in=$1 nat=$2 user=$3; shift 3
echo "$*" >> "${0%/*}/ipt.log"
case "$*" in
  "-S INPUT") f=$in ;;
  "-t nat -S DOCKER") f=$nat ;;
  "-S DOCKER-USER") f=$user ;;
  *) echo "fakeipt: unexpected $*" >&2; exit 2 ;;
esac
[ "$f" != - ] && exec cat "$f"
echo "iptables: No chain/target/match by that name." >&2
exit 1
EOF
ipt() { echo "sh $W/fakeipt $FX/$1 $2 $3"; }

# Legacy iptables, read beside an empty nftables ruleset
go "cat $FX/none.nft" "Tiger_IPT_Legacy_Cmd='`ipt legacy-drop.ipt - -`'"
has 'Incoming IPv4 traffic is denied by default (iptables-legacy INPUT: policy DROP).' && has '[fire002w]' &&
  ok "legacy iptables INPUT policy DROP counts for IPv4, not IPv6" || { bad "legacy iptables"; cat "$W/out"; }

# Docker: ports published on every address are forwarded before the input
# chain, so they are open even where fire003i says the host is closed
go "cat $FX/docker-hera.nft"
has "--WARN-- [fire005w] Port 2283/tcp, published by Docker on every IPv4 address, is open to the network: Docker forwards it before the input chain, and no rule restricts it. Forwarded to 172.18.0.5:2283. DOCKER-USER is empty. To restrict it, publish it on one address only (-p 127.0.0.1:2283:2283 keeps it on the host), or drop what should not reach it in DOCKER-USER, e.g. 'iptables -I DOCKER-USER -i eth0 ! -s YOUR-NETWORK -j DROP'." &&
  [ "`count fire005w`" = 1 ] && ok "Hera: Immich's 2283 is open over IPv4 (IPv6 goes to docker-proxy, a listener the input chain filters)" || { bad "docker on Hera"; cat "$W/out"; }
go "cat $FX/docker-xt.nft"
has '[fire005w] Port 8080/tcp, published by Docker on every IPv4 address' && has '[fire005w] Port 5353/udp, published by Docker on every IPv4 address' &&
  has '[fire005w] Port 8082/tcp, published by Docker on 172.17.0.2,' && has '[fire005w] Port 8443/tcp, published by Docker on every IPv6 address' &&
  [ "`count fire005w`" = 5 ] && [ "`count 8081`" = 0 ] && ! has 'Forwarded to' &&
  ok "TCP, UDP, one address and IPv6 each reported; the port on 127.0.0.1 is not; nft's \"xt target DNAT\" read too" || { bad "docker xt"; cat "$W/out"; }
go "cat $FX/docker27.nft"
has '[fire005w] Port 8080/tcp, published by Docker on every IPv4 address' && has 'DOCKER-USER is empty' &&
  ok "Docker 27: DOCKER-USER holding only its return counts as empty" || { bad "docker 27"; cat "$W/out"; }
go "cat $FX/docker-user.nft"
has '--INFO-- [fire006i] Docker publishes IPv4 ports to the network, and there are rules that may restrict them, which this check does not evaluate. Ports: 5353/udp, 8080/tcp, 8082/tcp, 8443/tcp. DOCKER-USER has 2 rules.' &&
  [ "`count 'fire005w.*IPv4'`" = 0 ] && has '[fire005w] Port 8443/tcp, published by Docker on every IPv6 address' &&
  ok "rules in DOCKER-USER: one INFO for IPv4, not evaluated; IPv6's DOCKER-USER is empty" || { bad "docker DOCKER-USER"; cat "$W/out"; }
go "cat $FX/docker-nftables.nft"
has "[fire005w] Port 8443/tcp, published by Docker on every IPv6 address, is open to the network: Docker forwards it before the input chain, and no rule restricts it. Forwarded to [fd00:dead::2]:443. Docker's nftables backend has no DOCKER-USER chain." &&
  [ "`count fire005w`" = 5 ] && ok "Docker's nftables backend (docker-bridges tables, dnat to)" || { bad "docker nftables backend"; cat "$W/out"; }
go "cat $FX/docker-nftables-filtered.nft"
has "Forward chains of the host's own that drop: nftables inet docker-filter forward." && [ "`count fire006i`" = 2 ] && [ "`count fire005w`" = 0 ] &&
  ok "a forward chain of one's own that drops: an INFO for each family" || { bad "docker nftables filtered"; cat "$W/out"; }

# ufw enabled beside Docker: the input chain drops, so fire003i, and yet
# the published ports answer (checked from outside the container: 8080
# answered, a listener on the host itself on 9999 did not)
go "cat $FX/docker-ufw.nft"
has 'Incoming IPv4 traffic is denied by default (nftables ip filter INPUT: policy drop).' &&
  has '[fire005w] Port 8080/tcp, published by Docker on every IPv4 address, is open to the network' && [ "`count fire005w`" = 5 ] &&
  ok "ufw enabled: denied by default, and Docker's ports still reported open" || { bad "docker and ufw"; cat "$W/out"; }

# Without nft (Ubuntu): iptables -S, and Docker's chains only when Docker runs
: > "$W/ipt.log"
go "" "Tiger_IPT_Cmd='`ipt input-accept.ipt $FX/docker-nat.ipt $FX/docker-user-rules.ipt`'" \
      "Tiger_IP6T_Cmd='`ipt input-accept.ipt $FX/docker-nat6.ipt $FX/docker-user-empty.ipt`'"
has '[fire001w] Incoming IPv4 traffic is not denied by default: no input chain drops what it does not accept. Input chains: iptables INPUT: policy ACCEPT.' &&
  [ "`count 'fire00[56]'`" = 0 ] && ! grep -q nat "$W/ipt.log" &&
  ok "iptables without nft: INPUT read, Docker's nat table not listed while Docker is not running" || { bad "iptables, no docker"; cat "$W/out" "$W/ipt.log"; }
go "" "Tiger_IPT_Cmd='`ipt input-accept.ipt - -`'" "Tiger_IP6T_Cmd='`ipt input-accept.ipt - -`'"
[ "`count fire007w`" = 2 ] && ok "iptables without a LOG rule: fire007w for both families" || { bad "iptables logging"; cat "$W/out"; }
mkdir -p "$W/sys/run"; : > "$W/sys/run/docker.sock"
go "" "Tiger_IPT_Cmd='`ipt input-accept.ipt $FX/docker-nat.ipt $FX/docker-user-rules.ipt`'" \
      "Tiger_IP6T_Cmd='`ipt input-accept.ipt $FX/docker-nat6.ipt $FX/docker-user-empty.ipt`'"
has 'Docker publishes IPv4 ports to the network, and there are rules that may restrict them, which this check does not evaluate. Ports: 5353/udp, 8080/tcp, 8082/tcp, 8443/tcp. DOCKER-USER has 2 rules.' &&
  has '[fire005w] Port 8443/tcp, published by Docker on every IPv6 address, is open to the network: Docker forwards it before the input chain, and no rule restricts it. Forwarded to [fd00:dead::2]:443.' &&
  ok "iptables without nft: DOCKER and DOCKER-USER read from iptables -S" || { bad "iptables docker"; cat "$W/out"; }
go "" "Tiger_IPT_Cmd='`ipt input-accept.ipt $FX/docker-nat.ipt $FX/docker27-user.ipt`'"
has '[fire005w] Port 8080/tcp, published by Docker on every IPv4 address' && has 'Forwarded to 172.18.0.2:80.' && [ "`count 8081`" = 0 ] &&
  has '[fire005w] Port 8082/tcp, published by Docker on 172.17.0.2,' &&
  ok "iptables -S: '-j RETURN' alone is an empty DOCKER-USER, -d 127.0.0.1/32 is left out" || { bad "iptables docker 27"; cat "$W/out"; }
# Legacy iptables: Docker's nat table only when the kernel has it loaded
: > "$W/ipt.log"
go "cat $FX/none.nft" "Tiger_IPT_Legacy_Cmd='`ipt legacy-drop.ipt $FX/docker-nat.ipt $FX/docker-user-empty.ipt`'"
[ "`count 'fire00[56]'`" = 0 ] && ! grep -q nat "$W/ipt.log" && ok "legacy: no nat in ip_tables_names, so it is not listed" || { bad "legacy, no nat"; cat "$W/out" "$W/ipt.log"; }
printf 'filter\nnat\n' > "$W/sys/proc/net/ip_tables_names"
go "cat $FX/none.nft" "Tiger_IPT_Legacy_Cmd='`ipt legacy-drop.ipt $FX/docker-nat.ipt $FX/docker-user-empty.ipt`'"
has 'Incoming IPv4 traffic is denied by default (iptables-legacy INPUT: policy DROP).' && has '[fire005w] Port 8080/tcp, published by Docker on every IPv4 address' &&
  ok "legacy: denied by default, and Docker's ports still open" || { bad "legacy docker"; cat "$W/out"; }
rm -f "$W/sys/proc/net/ip_tables_names" "$W/sys/run/docker.sock"

# IPv6 switched off: nothing to say about it
echo 1 > "$W/sys/proc/sys/net/ipv6/conf/all/disable_ipv6"
go "cat $FX/none.nft"
has '[fire001w]' && [ "`count fire002w`" = 0 ] && ok "IPv6 disabled: no IPv6 finding" || { bad "IPv6 disabled"; cat "$W/out"; }
go "cat $FX/docker-xt.nft"
[ "`count 'fire005w.*IPv6'`" = 0 ] && [ "`count fire005w`" = 4 ] && ok "IPv6 disabled: Docker's IPv6 ports are not reported" || { bad "IPv6 disabled, docker"; cat "$W/out"; }
echo 0 > "$W/sys/proc/sys/net/ipv6/conf/all/disable_ipv6"

# The ruleset cannot be read (not root): an ERROR, and no guess
printf '#!/bin/sh\necho "Error: Operation not permitted" >&2\nexit 1\n' > "$W/nft-denied"
go "sh $W/nft-denied"
has '--ERROR-- [fire004e] The nftables ruleset could not be read' && has 'Error: Operation not permitted' &&
  [ "`count 'fire00[123]'`" = 0 ] && ok "an unreadable ruleset is an ERROR (fire004e) with nft's reason, not a WARN" || { bad "unreadable ruleset"; cat "$W/out"; }

# The advice names what is installed
go "cat $FX/none.nft" "Tiger_Firewall_Frontends='ufw'"
has "ufw is installed: 'ufw enable' turns on its default-deny policy." && ok "with ufw installed, the advice is 'ufw enable'" || { bad "ufw advice"; cat "$W/out"; }
go "cat $FX/none.nft" "Tiger_Firewall_Frontends='firewalld'"
has "firewalld is installed: 'systemctl enable --now firewalld'" && ok "with firewalld installed, the advice is to start it" || { bad "firewalld advice"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
