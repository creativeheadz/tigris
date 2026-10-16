#!/bin/sh
#
# tests/crypto_check.sh - check_crypto on offline roots, plus a live
# proc tree
#
# Four roots: an rng daemon feeding from urandom; a readable private
# key beside a certificate and an OpenSSH host key left readable;
# locked-down equivalents (a hardware device, keys alone); and an
# empty root, where there is nothing to judge. A fifth leg reads a
# fixture /proc through Tigris_Sysctl_Root for the pool level, and a
# sixth proves it stays silent under --root. INFO findings only show
# with Tigris_Show_INFO_Msgs=Y. Runs as a user and as root; the
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
run() {  # run ROOT OUTFILE [SYSROOT]: check_crypto with ROOT audited
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { echo "Tigris_Show_INFO_Msgs=Y"; [ -n "$3" ] && echo "Tigris_Sysctl_Root='$3'"; } >> "$W/tigris.conf"
  if [ -n "$3" ]; then
    ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_crypto ) 2>&1
  else
    ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/Linux/2/check_crypto ) 2>&1
  fi |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }

R=$W/rng; mkdir -p "$R/etc/default"
printf '# feeding the daemon from itself\nHRNGDEVICE=/dev/urandom\n' > "$R/etc/default/rng-tools"
run "$R" "$W/out"
has "--WARN-- [cry001w] The random-number daemon feeds from \`/dev/urandom' (/etc/default/rng-tools):" "$W/out" &&
  ok "rngd feeding from urandom: cry001w" || { bad "rng"; cat "$W/out"; }

K=$W/keys; mkdir -p "$K/etc/ssl/private" "$K/etc/ssh"
printf -- '-----BEGIN RSA PRIVATE KEY-----\nxxxx\n' > "$K/etc/ssl/private/server.key"
chmod 644 "$K/etc/ssl/private/server.key"
printf -- '-----BEGIN CERTIFICATE-----\nxxxx\n' > "$K/etc/ssl/private/server.crt"
printf 'ssh-ed25519 AAAAC3NzfX user@host\n' > "$K/etc/ssh/ssh_host_ed25519_key.pub"
printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nxxxx\n' > "$K/etc/ssh/ssh_host_ed25519_key"
chmod 600 "$K/etc/ssh/ssh_host_ed25519_key"
run "$K" "$W/out"
has "--WARN-- [cry002w] The private key in \`/etc/ssl/private/server.key' is readable by anyone:" "$W/out" &&
  [ "`grep -c 'cry002w' \"$W/out\"`" = 1 ] &&
  ok "a readable key among a cert and a locked host key: one cry002w" || { bad "keys"; cat "$W/out"; }

G=$W/good; mkdir -p "$G/etc/default" "$G/etc/ssl/private"
printf 'HRNGDEVICE=/dev/hwrng\n' > "$G/etc/default/rng-tools"
printf -- '-----BEGIN RSA PRIVATE KEY-----\nxxxx\n' > "$G/etc/ssl/private/server.key"
chmod 600 "$G/etc/ssl/private/server.key"
run "$G" "$W/out"
grep -q 'cry001w\|cry002w' "$W/out" && { bad "good"; cat "$W/out"; } ||
  ok "a hardware device and a key alone: nothing"

E=$W/empty; mkdir -p "$E/etc"
run "$E" "$W/out"
[ -s "$W/out" ] && { bad "empty"; cat "$W/out"; } ||
  ok "no RNG config and no keys: nothing said"

V=$W/proc; mkdir -p "$V/proc/sys/kernel/random"
printf '1536\n' > "$V/proc/sys/kernel/random/entropy_avail"
printf '4096\n' > "$V/proc/sys/kernel/random/poolsize"
run "" "$W/live.out" "$V"
has '[cry003i]' "$W/live.out" && has 'holds 1536 of 4096 bits' "$W/live.out" &&
  ok "a fixture /proc: the pool level" || { bad "live"; cat "$W/live.out"; }

run "$G" "$W/root.out"
! grep -q 'cry003i' "$W/root.out" &&
  ok "under --root the live leg stays silent" || { bad "root"; cat "$W/root.out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
