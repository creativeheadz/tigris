#!/bin/sh
#
# tests/network_config_check.sh - check_network_config's kernel settings
#
# Offline roots whose sysctl.d sets the values in question, run through
# the check as tigris --root would. The kernel's own rules decide:
# source-routed packets are accepted on an interface only when
# conf/all/accept_source_route and the interface's are both on, so the
# stock Ubuntu pair (all 0, default 1) is no finding, though either one on
# was a FAIL on every Ubuntu host until October 2026; reverse-path
# filtering takes the higher of conf/all and the interface's rp_filter, so
# only both at 0 is lin014f (the default's half was read from a path that
# does not exist), and a higher value of 2 is loose mode, lin051w, where
# CIS 3.3.7 wants strict. Live legs run on a /proc tree of their own
# (Tigris_Sysctl_Root): interfaces judged one by one, proxy ARP, multicast
# routing. icmp_ignore_bogus_error_responses is check_sysctl's (lin033w):
# this check says nothing of it.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

root()  # root NAME SETTINGS...: a root whose sysctl.d sets these
{
  r=$W/$1; shift
  mkdir -p "$r/etc/sysctl.d"
  for s; do echo "$s"; done > "$r/etc/sysctl.d/90-test.conf"
}
ids()  # ids NAME: the finding ids the check gives for that root
{
  ( cd "$W" && TIGRIS_ROOT="$W/$1" TIGERHOMEDIR="$W" sh ./systems/Linux/2/check_network_config ) 2>&1 |
    grep -o '^--[A-Z]*-- \[[a-z0-9]*\]' | sed 's/.*\[//; s/\]//' | sort -u | tr '\n' ' '
}

root stock   net.ipv4.conf.all.accept_source_route=0 net.ipv4.conf.default.accept_source_route=1 \
             net.ipv4.conf.all.rp_filter=2 net.ipv4.conf.default.rp_filter=2
root srcboth net.ipv4.conf.all.accept_source_route=1 net.ipv4.conf.default.accept_source_route=1
root srcall  net.ipv4.conf.all.accept_source_route=1 net.ipv4.conf.default.accept_source_route=0
root rpoff   net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.default.rp_filter=0
root rphalf  net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.default.rp_filter=1
root bogus   net.ipv4.icmp_ignore_bogus_error_responses=0
root strict  net.ipv4.conf.all.rp_filter=1 net.ipv4.conf.default.rp_filter=1
root rpmixed net.ipv4.conf.all.rp_filter=1 net.ipv4.conf.default.rp_filter=2
root rploose net.ipv4.conf.all.rp_filter=2
root proxy   net.ipv4.conf.all.proxy_arp=1
root mcast   net.ipv4.conf.all.mc_forwarding=1

case " `ids stock` " in *" lin016f "*) bad "stock Ubuntu (all 0, default 1): lin016f" ;; *) ok "stock Ubuntu's source routing (all 0, default 1): no lin016f" ;; esac
case " `ids srcboth` " in *" lin016f "*) ok "all and default on: lin016f" ;; *) bad "all and default on: no lin016f" ;; esac
case " `ids srcall` " in *" lin016f "*) bad "all on, default off: lin016f" ;; *) ok "all on, default off, no interface to look at offline: no lin016f" ;; esac
case " `ids rpoff` " in *" lin014f "*) ok "rp_filter off in all and default: lin014f" ;; *) bad "rp_filter off in both: no lin014f" ;; esac
case " `ids rphalf` " in *" lin014f "*|*" lin051w "*) bad "rp_filter all 0, default 1: `ids rphalf`" ;; *) ok "rp_filter all 0, default 1 (strict wins): nothing" ;; esac
case " `ids stock` " in *" lin014f "*) bad "stock Ubuntu's rp_filter 2: lin014f" ;; *) ok "stock Ubuntu's rp_filter (2, loose): no lin014f" ;; esac
case " `ids stock` " in *" lin051w "*) ok "stock Ubuntu's rp_filter (2, loose): lin051w, CIS 3.3.7 wants strict" ;; *) bad "stock Ubuntu's rp_filter 2: no lin051w" ;; esac
[ "`ids strict`" = "" ] && ok "rp_filter 1 and 1: nothing" || bad "strict rp_filter: `ids strict`"
case " `ids rpmixed` " in *" lin051w "*) ok "rp_filter all 1, default 2: the higher value counts, lin051w" ;; *) bad "all 1, default 2: no lin051w" ;; esac
case " `ids rploose` " in *" lin051w "*) ok "rp_filter all 2, default unset: loose whatever the default, lin051w" ;; *) bad "all 2, default unset: no lin051w" ;; esac
# check_sysctl judges this one (lin033w): nothing here, so it is said once
[ -z "`ids bogus`" ] && ok "bogus ICMP errors logged: left to check_sysctl" || bad "bogus ICMP errors: `ids bogus`"
case " `ids proxy` " in *" lin052w "*) ok "proxy ARP on conf/all from its sysctl.d: lin052w" ;; *) bad "proxy_arp=1: no lin052w" ;; esac
[ "`ids mcast`" = "" ] && ok "mc_forwarding in sysctl.d: not judged offline (a daemon sets it, not sysctl)" || bad "offline mc_forwarding: `ids mcast`"

# Live, on a /proc of its own: conf/all, conf/default, lo and two
# interfaces. The settings everyone has right are written so, and
# nothing else, so a missing file is the kernel's lacking it: unknown,
# no finding
live()  # live NAME: a /proc/sys tree; then set NAME KEY VALUE
{
  L=$W/$1; mkdir -p "$L/proc/sys/net/ipv4/conf/all" "$L/proc/sys/net/ipv4/conf/default" "$L/proc/sys/net/ipv4/conf/lo" "$L/proc/sys/net/ipv4/conf/eth0" "$L/proc/sys/net/ipv4/conf/docker0"
  for i in all default lo eth0 docker0
  do
    echo 0 > "$L/proc/sys/net/ipv4/conf/$i/accept_redirects"; echo 0 > "$L/proc/sys/net/ipv4/conf/$i/accept_source_route"
    echo 1 > "$L/proc/sys/net/ipv4/conf/$i/log_martians"; echo 1 > "$L/proc/sys/net/ipv4/conf/$i/rp_filter"
    echo 0 > "$L/proc/sys/net/ipv4/conf/$i/proxy_arp"
  done
  echo 1 > "$L/proc/sys/net/ipv4/icmp_echo_ignore_broadcasts"; echo 1 > "$L/proc/sys/net/ipv4/tcp_syncookies"; echo 0 > "$L/proc/sys/net/ipv4/ip_forward"
}
setv() { echo "$3" > "$W/$1/proc/sys/$2"; }
lids()  # lids NAME: the finding ids live on that tree, and the text in $W/live.out
{
  cp "$W/tigris.conf" "$W/tigris.conf.keep"
  echo "Tigris_Sysctl_Root='$W/$1'" >> "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR="$W" sh ./systems/Linux/2/check_network_config ) 2>&1 |
    awk '/^--/ { if (l != "") print l; l = $0; next } /^[ \t]/ { sub(/^[ \t]+/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' | tr -s ' ' > "$W/live.out"
  mv "$W/tigris.conf.keep" "$W/tigris.conf"
  grep -o '^--[A-Z]*-- \[[a-z0-9]*\]' "$W/live.out" | sed 's/.*\[//; s/\]//' | sort -u | tr '\n' ' '
}
live clean
[ "`lids clean`" = "" ] && ok "live, everything strict and off: nothing (and missing files are no finding)" || { bad "live clean: `lids clean`"; cat "$W/live.out"; }
live ifloose; setv ifloose net/ipv4/conf/docker0/rp_filter 2
case " `lids ifloose` " in *" lin051w "*) grep -q 'Loose on: .*docker0\.' "$W/live.out" && ok "live: one interface loose while all and default are strict: lin051w names it" || { bad "lin051w names: `grep lin051w "$W/live.out"`"; } ;; *) bad "live docker0 loose: `lids ifloose`" ;; esac
live ifoff; setv ifoff net/ipv4/conf/all/rp_filter 0; setv ifoff net/ipv4/conf/eth0/rp_filter 0
case " `lids ifoff` " in *" lin014f "*) grep -q 'Unfiltered: .*eth0\.' "$W/live.out" && ! grep -q 'new interfaces' "$W/live.out" && ok "live: all 0 and eth0 0: lin014f names eth0, not the default (1)" || { bad "lin014f names: `grep lin014f "$W/live.out"`"; } ;; *) bad "live eth0 off: `lids ifoff`" ;; esac
live allloose; setv allloose net/ipv4/conf/all/rp_filter 2
case " `lids allloose` " in *" lin051w "*) grep -q 'Loose on: new interfaces (conf/default), docker0, eth0\.' "$W/live.out" && ok "live: all 2 makes every interface loose, each named" || { bad "all 2 names: `grep lin051w "$W/live.out"`"; } ;; *) bad "live all loose: `lids allloose`" ;; esac
live proxy; setv proxy net/ipv4/conf/all/proxy_arp 1
case " `lids proxy` " in *" lin052w "*) ok "live: proxy ARP on conf/all: lin052w" ;; *) bad "live proxy_arp: `lids proxy`" ;; esac
live mcast; setv mcast net/ipv4/conf/all/mc_forwarding 1
case " `lids mcast` " in *" lin053w "*) ok "live: mc_forwarding on, a multicast routing daemon: lin053w" ;; *) bad "live mc_forwarding: `lids mcast`" ;; esac
setv mcast net/ipv4/conf/all/mc_forwarding 0
[ "`lids mcast`" = "" ] && ok "live: mc_forwarding 0: nothing" || bad "live mc_forwarding 0: `lids mcast`"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
