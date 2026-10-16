#!/bin/sh
#
# tests/offline_release_check.sh - the release check, on roots made of
# the real release files of current and past distributions
#
# Each root holds what the distribution's own image holds (os-release as
# shipped, debian_version, redhat-release), and the date is fixed
# (Tigris_Today) so the verdicts do not drift as releases age. A supported
# release says nothing; one past the end of its security support is
# osv002f, naming the date and any paid extended support; Debian testing
# is osv004w; Red Hat Linux, before RHEL, is osv001f. Ubuntu's
# debian_version says "trixie/sid" and must not read as Debian testing;
# RHEL's family and Fedora were misread from redhat-release until
# October 2026. One full run checks the JSON against the schema and that
# no finding names where the root is on this host.
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
uid=`id -u`
[ "$uid" = 0 ] && chown -R 0:0 "$W"

# root NAME FILE CONTENT [FILE CONTENT...]: a root holding these files
root()
{
  r=$W/$1; shift
  mkdir -p "$r/etc"
  while [ $# -ge 2 ]
  do
    printf '%s\n' "$2" > "$r/etc/$1"; shift 2
  done
}
osr() { printf 'NAME="%s"\nID=%s\n%s' "$1" "$2" "${3:+VERSION_ID=\"$3\"}"; }

root deb13    os-release "`osr 'Debian GNU/Linux' debian 13`" debian_version 13.7
root deb11    os-release "`osr 'Debian GNU/Linux' debian 11`" debian_version 11.11
root debsid   os-release "`osr 'Debian GNU/Linux' debian`"    debian_version trixie/sid
root deb8old  debian_version 8.11
root ubu2404  os-release "`osr Ubuntu ubuntu 24.04`" debian_version trixie/sid
root ubu2004  os-release "`osr Ubuntu ubuntu 20.04`" debian_version bullseye/sid
root rocky93  os-release "`osr 'Rocky Linux' rocky 9.3`" redhat-release 'Rocky Linux release 9.3 (Blue Onyx)'
root alma98   os-release "`osr AlmaLinux almalinux 9.8`" redhat-release 'AlmaLinux release 9.8 (Olive Jaguar)'
root stream8  os-release "`osr 'CentOS Stream' centos 8`" redhat-release 'CentOS Stream release 8'
root centos7  os-release "`osr 'CentOS Linux' centos 7`" redhat-release 'CentOS Linux release 7.9.2009 (Core)'
root fed44    os-release "`osr 'Fedora Linux' fedora 44`" redhat-release 'Fedora release 44 (Forty Four)'
root fed40    os-release "`osr 'Fedora Linux' fedora 40`" redhat-release 'Fedora release 40 (Forty)'
root alp324   os-release "`osr 'Alpine Linux' alpine 3.24.2`" alpine-release 3.24.2
root alp318   os-release "`osr 'Alpine Linux' alpine 3.18.4`" alpine-release 3.18.4
root arch     os-release "`osr 'Arch Linux' arch 20260927.0.600689`"
root redhat71 redhat-release 'Red Hat Linux release 7.1 (Seawolf)'

join() {
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--'
}
check() {  # check ROOT: check_release's findings for that root
  ( cd "$W" && TIGRIS_ROOT="$W/$1" TIGERHOMEDIR="$W" Tigris_Today=20261010 sh ./systems/Linux/2/check_release ) 2>&1 | join
}
quiet() {  # quiet ROOT WHY
  out=`check "$1"`
  [ -z "$out" ] && ok "$2: nothing to say" || { bad "$2: $out"; }
}
says() {   # says ROOT TEXT WHY
  out=`check "$1"`
  case "$out" in *"$2"*) ok "$3" ;; *) bad "$3: got [$out]" ;; esac
}

quiet deb13   "Debian 13"
says  deb11   "[osv002f] Debian GNU/Linux 11 has had no security updates since 2026-08-31. Paid extended support for it runs until 2031-06-30" \
  "Debian 11: osv002f, its end of support and its paid extension"
says  debsid  "[osv004w] This is Debian testing or unstable (trixie/sid)" "Debian testing: osv004w"
says  deb8old "[osv002f] Debian GNU/Linux 8 has had no security updates since 2020-06-30" "Debian 8 with no os-release: osv002f from debian_version"
quiet ubu2404 "Ubuntu 24.04, whose debian_version says trixie/sid"
says  ubu2004 "[osv002f] Ubuntu 20.04 has had no security updates since 2025-05-31. Paid extended support for it runs until 2030-04-23" \
  "Ubuntu 20.04: osv002f, with ESM's date"
quiet rocky93 "Rocky Linux 9.3"
quiet alma98  "AlmaLinux 9.8"
says  stream8 "[osv002f] CentOS Stream 8 has had no security updates since 2024-05-31" "CentOS Stream 8 (os-release says centos): osv002f"
says  centos7 "[osv002f] CentOS Linux 7 has had no security updates since 2024-06-30" "CentOS 7: osv002f"
quiet fed44   "Fedora 44"
says  fed40   "[osv002f] Fedora Linux 40 has had no security updates since" "Fedora 40: osv002f"
quiet alp324  "Alpine 3.24.2, found as 3.24"
says  alp318  "[osv002f] Alpine Linux 3.18.4 has had no security updates since" "Alpine 3.18.4: osv002f"
quiet arch    "Arch, a rolling release"
says  redhat71 "[osv001f] This is Red Hat Linux release 7.1 (Seawolf), which has had no security updates since 2004" "Red Hat Linux 7.1: osv001f"

# One full run, for the JSON and the paths
{
  sed -n 's/^\(Tigris_Check_[A-Z_]*\)=.*/\1=N/p' "$W/tigris.conf"
  echo 'Tigris_Deb_CheckMD5Sums=N'; echo 'Tigris_Deb_NoPackFiles=N'; echo 'Tigris_Deb_StatOverride=N'
  echo 'Tigris_Check_SYSTEM=Y'; echo 'Tigris_Check_OS=Y'; echo 'Tigris_Today=20261010'
} > "$W/profiles/release"
chmod 644 "$W/profiles/release"
( cd "$W" && sh ./tigris -q --profile release --root "$W/deb11" ) > "$W/out" 2>&1
json=`ls -t "$W"/log/*.jsonl 2>/dev/null | head -1`
if [ -n "$json" ]; then
  grep -q '"id":"osv002f".*Debian GNU/Linux 11 has had no security updates since 2026-08-31' "$json" && ok "a full run reports it in the JSON" || bad "full run: no osv002f"
  grep '"type":"finding"' "$json" | grep -q "$W/deb11" && bad "a finding names the root's directory on this host" || ok "findings name the root's own paths"
  sh "$W/tests/schema_check.sh" "$json" > "$W/schema.out" 2>&1 && ok "the report validates" ||
    { grep -q SKIP "$W/schema.out" && ok "(schema not checked: $(cat "$W/schema.out"))" || { bad "schema"; cat "$W/schema.out"; }; }
else
  bad "no report:"; cat "$W/out"
fi

[ $fail -eq 0 ] && echo "PASS"
exit $fail
