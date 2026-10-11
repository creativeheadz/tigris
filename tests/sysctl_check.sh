#!/bin/sh
#
# tests/sysctl_check.sh - check_sysctl against a tree of known values
#
# Builds a fake /proc/sys with every setting at its worst value and checks
# that each message code appears, then one with every setting right and
# checks that nothing is reported. Needs no root and touches nothing
# outside a temporary directory.
#
# Exit 0 when every assertion holds, 1 otherwise.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write

W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"

# key value  (bad)        key value  (good)
settings='
kernel/kptr_restrict                        0 2
kernel/dmesg_restrict                       0 1
kernel/yama/ptrace_scope                    0 1
kernel/randomize_va_space                   0 2
kernel/sysrq                                1 176
kernel/unprivileged_bpf_disabled            0 2
kernel/perf_event_paranoid                  1 3
fs/suid_dumpable                            1 2
fs/protected_hardlinks                      0 1
fs/protected_symlinks                       0 1
fs/protected_fifos                          0 2
fs/protected_regular                        0 2
net/ipv4/conf/all/send_redirects            1 0
net/ipv4/conf/default/send_redirects        1 0
net/ipv4/icmp_ignore_bogus_error_responses  0 1
net/ipv6/conf/all/accept_redirects          1 0
net/ipv6/conf/default/accept_redirects      1 0
net/ipv6/conf/all/accept_source_route       1 0
net/ipv6/conf/default/accept_source_route   1 0
'
expected="lin020w lin021w lin022w lin023f lin024w lin025w lin026w lin027w lin028f lin029f lin030w lin031w lin032w lin033w lin034w lin035f lin036w"

build()
{
  # $1 = tree, $2 = column (2 bad, 3 good)
  echo "$settings" | while read key bad good
  do
    [ -z "$key" ] && continue
    mkdir -p "$1/proc/sys/`dirname $key`"
    if [ "$2" = 2 ]; then echo "$bad"; else echo "$good"; fi > "$1/proc/sys/$key"
  done
  # the kernel's CPU vulnerability verdicts
  mkdir -p "$1/sys/devices/system/cpu/vulnerabilities"
  echo "Not affected" > "$1/sys/devices/system/cpu/vulnerabilities/meltdown"
  echo "Mitigation: Retpolines; IBPB: conditional" > "$1/sys/devices/system/cpu/vulnerabilities/spectre_v2"
  if [ "$2" = 2 ]; then echo "Vulnerable: No microcode"; else echo "Mitigation: Clear CPU buffers"; fi > "$1/sys/devices/system/cpu/vulnerabilities/mds"
}

run()
{
  # $1 = tree. The setting goes in the copy's tigerrc, which config exports
  echo "Tiger_Sysctl_Root='$1'" >> "$W/tigerrc"
  ( cd "$W" && TIGERHOMEDIR=$W sh systems/Linux/2/check_sysctl 2>&1 )
  sed -i '$d' "$W/tigerrc"
}

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
build "$W/bad" 2
run "$W/bad" > "$W/bad.out"
for code in $expected
do
  if grep -q "\[$code\]" "$W/bad.out"; then
    echo "ok   $code reported for the bad value"
  else
    echo "FAIL $code missing"; fail=1
  fi
done

build "$W/good" 3
run "$W/good" > "$W/good.out"
if grep -q -- '--\(WARN\|FAIL\|ALERT\)--' "$W/good.out"; then
  echo "FAIL good tree still reported:"; grep -- '--' "$W/good.out" | head; fail=1
else
  echo "ok   nothing reported for the good tree"
fi

# A kernel without a knob is not a finding
rm "$W/good/proc/sys/kernel/unprivileged_bpf_disabled"
run "$W/good" > "$W/missing.out"
if grep -q -- '--\(WARN\|FAIL\|ALERT|ERROR\)--' "$W/missing.out"; then
  echo "FAIL a missing setting was reported"; fail=1
else
  echo "ok   a missing setting is skipped"
fi

# An offline root (TIGRIS_ROOT, as tigris --root sets it): no /proc/sys of
# its own, so the settings it applies at boot, from its sysctl.d files the
# way systemd-sysctl layers them, for check_sysctl and check_network_config
R=$W/img
mkdir -p "$R/etc/sysctl.d" "$R/usr/lib/sysctl.d"
printf 'net.ipv4.ip_forward = 1\nkernel/sysrq=1\n' > "$R/usr/lib/sysctl.d/50-vendor.conf"
printf 'net.ipv4.ip_forward=0\n' > "$R/etc/sysctl.d/50-vendor.conf"
printf -- '-net.ipv4.conf.*.accept_redirects = 1\n; a comment\nkernel.randomize_va_space = 1\n' > "$R/etc/sysctl.d/60-local.conf"
printf 'kernel.dmesg_restrict = 0\n' > "$R/etc/sysctl.conf"
echo "Tiger_Show_INFO_Msgs=Y" >> "$W/tigerrc"
for c in check_sysctl check_network_config
do
  ( cd "$W" && TIGRIS_ROOT=$R TIGERHOMEDIR=$W sh systems/Linux/2/$c 2>&1 )
done | awk '/^--/ { if (l != "") print l; l = $0; next } /^[ \t]/ { sub(/^[ \t]+/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' > "$W/root.out"
has() { grep -F -q -- "$1" "$W/root.out"; }
has '[lin023f] kernel.randomize_va_space is 1 (set in /etc/sysctl.d/60-local.conf)' &&
  ok "offline root: a setting from its sysctl.d, naming the file: lin023f" || bad "offline lin023f"
has '[lin021w] kernel.dmesg_restrict is 0 (set in /etc/sysctl.conf)' && ok "offline root: /etc/sysctl.conf, read last" || bad "offline sysctl.conf"
has 'kernel.sysrq is' && bad "offline root: a vendor file replaced by one of the same name in /etc was read" ||
  ok "offline root: /etc/sysctl.d/50-vendor.conf replaces the vendor's file of that name"
has '[lin015w]' && bad "offline root: ip_forward from the replaced file" || ok "offline root: the replacing file's ip_forward=0 holds"
has '[lin012w] The system accepts ICMP redirection messages' &&
  ok "offline root: a glob (net.ipv4.conf.*.accept_redirects) reaches all and default: lin012w" || bad "offline glob"
has '[lin041i]' && has 'kernel.kptr_restrict' && ok "offline root: settings nothing sets are listed, not guessed: lin041i" || bad "offline lin041i"
has '[lin013f]' && bad "offline root: an unset tcp_syncookies was taken for 0" || ok "offline root: an unset setting is no finding"

[ $fail -eq 0 ] && echo "PASS" || { echo "--- bad.out"; cat "$W/bad.out"; echo "--- root.out"; cat "$W/root.out"; }
exit $fail
