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
# does not exist).
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

case " `ids stock` " in *" lin016f "*) bad "stock Ubuntu (all 0, default 1): lin016f" ;; *) ok "stock Ubuntu's source routing (all 0, default 1): no lin016f" ;; esac
case " `ids srcboth` " in *" lin016f "*) ok "all and default on: lin016f" ;; *) bad "all and default on: no lin016f" ;; esac
case " `ids srcall` " in *" lin016f "*) bad "all on, default off: lin016f" ;; *) ok "all on, default off, no interface to look at offline: no lin016f" ;; esac
case " `ids rpoff` " in *" lin014f "*) ok "rp_filter off in all and default: lin014f" ;; *) bad "rp_filter off in both: no lin014f" ;; esac
case " `ids rphalf` " in *" lin014f "*) bad "rp_filter all 0, default 1: lin014f" ;; *) ok "rp_filter all 0, default 1: no lin014f" ;; esac
case " `ids stock` " in *" lin014f "*) bad "stock Ubuntu's rp_filter 2: lin014f" ;; *) ok "stock Ubuntu's rp_filter (2, loose): no lin014f" ;; esac

[ $fail -eq 0 ] && echo "PASS"
exit $fail
