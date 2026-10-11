#!/bin/sh
#
# tests/secureboot_check.sh - check_secureboot against /sys trees of its own
#
# Each case is a /sys with the firmware's SecureBoot and SetupMode
# variables written the way efivarfs shows them (four attribute bytes,
# then the value; the desktop's say 6 0 0 0 1) and a lockdown file, fed through
# Tiger_Sysctl_Root. Needs no root, no UEFI and no Secure Boot.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
cp "$W/tigerrc" "$W/tigerrc.base"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
GUID=8be4df61-93ca-11d2-aa0d-00e098032b8c

# tree NAME SECUREBOOT SETUPMODE LOCKDOWN: "-" leaves a part out
tree() {
  t="$W/$1"; mkdir -p "$t/sys/firmware/acpi"
  if [ "$2" != nobios ]; then
    mkdir -p "$t/sys/firmware/efi/efivars"
    [ "$2" != - ] && printf "\\006\\000\\000\\000\\00$2" > "$t/sys/firmware/efi/efivars/SecureBoot-$GUID"
    [ "$3" != - ] && printf "\\006\\000\\000\\000\\00$3" > "$t/sys/firmware/efi/efivars/SetupMode-$GUID"
  fi
  [ "$4" != - ] && { mkdir -p "$t/sys/kernel/security"; echo "$4" > "$t/sys/kernel/security/lockdown"; }
  :
}
go() {  # go NAME: run the check on that tree, findings to $W/out
  cp "$W/tigerrc.base" "$W/tigerrc"
  echo "Tiger_Sysctl_Root='$W/$1'" >> "$W/tigerrc"
  echo "Tiger_Show_INFO_Msgs=Y" >> "$W/tigerrc"
  ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_secureboot ) 2>&1 |
    awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
    tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out"
}
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -c -- "$1" "$W/out"; }

tree locked 1 0 "none [integrity] confidentiality"; go locked
has '--INFO-- [boot012i] Secure Boot is on, and kernel lockdown is integrity.' && [ "`count .`" = 1 ] &&
  ok "Secure Boot on, lockdown integrity (the desktop): one INFO" || { bad "locked"; cat "$W/out"; }
tree open 1 0 "[none] integrity confidentiality"; go open
has 'Secure Boot is on, and kernel lockdown is none.' &&
  has '--WARN-- [lin040w] Secure Boot is on, but the kernel is not locked down: root can still change the running kernel, which undoes what Secure Boot verified. Lockdown is none.' &&
  ok "Secure Boot on, lockdown none: lin040w" || { bad "lockdown none"; cat "$W/out"; }
tree nolsm 1 0 -; go nolsm
has 'kernel lockdown is not supported by this kernel.' && has '[lin040w]' && has 'Lockdown is not built into this kernel.' &&
  ok "Secure Boot on, a kernel without lockdown: lin040w" || { bad "no lockdown LSM"; cat "$W/out"; }
tree off 0 0 "[none] integrity confidentiality"; go off
has '--WARN-- [boot009w] Secure Boot is off: the firmware starts any boot loader and kernel, signed or not.' && [ "`count lin040w`" = 0 ] &&
  ok "Secure Boot off: boot009w, and nothing about lockdown" || { bad "off"; cat "$W/out"; }
tree setup 0 1 -; go setup
has '--WARN-- [boot011w] The firmware is in Secure Boot setup mode' && [ "`count boot009w`" = 0 ] &&
  ok "setup mode: boot011w, not also boot009w" || { bad "setup mode"; cat "$W/out"; }
tree bios nobios - -; go bios
has '--INFO-- [boot010i] The system booted without UEFI (legacy BIOS)' && [ "`count .`" = 1 ] &&
  ok "no UEFI: boot010i" || { bad "bios"; cat "$W/out"; }
tree novars - - -; go novars
has '--ERROR-- [boot013e] Whether Secure Boot is on cannot be told' &&
  ok "UEFI, variables unreadable: boot013e" || { bad "no efivars"; cat "$W/out"; }
mkdir -p "$W/container/sys/firmware"; go container
[ "`count .`" = 0 ] && ok "an empty /sys/firmware (a container): nothing said" || { bad "container"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
