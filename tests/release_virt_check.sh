#!/bin/sh
#
# tests/release_virt_check.sh - the guest-detection leg of check_release
#
# Four fixture /sys+proc trees, read through Tigris_Sysctl_Root the way
# the promisc suite reads its sysfs: a Xen domU (hypervisor type file),
# a VMware guest (DMI vendor and product), a guest on no recognized
# platform (only the hypervisor bit in cpuinfo), and bare metal (none
# of the three). A fifth leg sets TIGRIS_ROOT over the Xen tree: the
# leg describes the auditing host, never a root, so it stays silent.
# INFO findings only show with Tigris_Show_INFO_Msgs=Y. Runs as a user
# and as root; sysfs and cpuinfo read the same for both.
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
run() {  # run TREE OUTFILE [ROOT]: check_release with /proc and /sys under TREE
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { echo "Tigris_Sysctl_Root='$1'"; echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
  {
    if [ -n "$3" ]; then
      ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$3" sh ./systems/Linux/2/check_release ) 2>&1
    else
      ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_release ) 2>&1
    fi
  } |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep -- '--INFO-- \[osv003i\]\|--WARN-- \[osv\|--FAIL-- \[osv' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }

X=$W/xen
mkdir -p "$X/sys/hypervisor"
printf 'xen\n' > "$X/sys/hypervisor/type"
run "$X" "$W/out"
has "[osv003i] This machine is a virtual guest (xen)" "$W/out" &&
  ok "a Xen domU: osv003i names xen" || { bad "xen"; cat "$W/out"; }

V=$W/vmware
mkdir -p "$V/sys/devices/virtual/dmi/id" "$V/proc"
printf 'VMware, Inc.\n' > "$V/sys/devices/virtual/dmi/id/sys_vendor"
printf 'VMware Virtual Platform\n' > "$V/sys/devices/virtual/dmi/id/product_name"
printf 'processor\t: 0\nflags\t\t: fpu hypervisor tsc\n' > "$V/proc/cpuinfo"
run "$V" "$W/out"
has "[osv003i] This machine is a virtual guest (vmware)" "$W/out" &&
  ok "DMI names VMware: osv003i names vmware" || { bad "vmware"; cat "$W/out"; }

U=$W/unknown
mkdir -p "$U/proc"
printf 'processor\t: 0\nflags\t\t: fpu hypervisor tsc\n' > "$U/proc/cpuinfo"
run "$U" "$W/out"
has "[osv003i] This machine is a virtual guest (unknown)" "$W/out" &&
  ok "only the hypervisor bit: osv003i names unknown" || { bad "unknown"; cat "$W/out"; }

B=$W/bare
mkdir -p "$B/proc" "$B/sys/devices/virtual/dmi/id"
printf 'processor\t: 0\nflags\t\t: fpu tsc\n' > "$B/proc/cpuinfo"
printf 'LENOVO\n' > "$B/sys/devices/virtual/dmi/id/sys_vendor"
printf 'ThinkPad X1\n' > "$B/sys/devices/virtual/dmi/id/product_name"
run "$B" "$W/out"
grep -q 'osv003i' "$W/out" && { bad "bare"; cat "$W/out"; } ||
  ok "bare metal, no hypervisor bit: nothing"

run "$X" "$W/root.out" "$X"
grep -q 'osv003i' "$W/root.out" && { bad "root"; cat "$W/root.out"; } ||
  ok "under --root the live leg stays silent"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
