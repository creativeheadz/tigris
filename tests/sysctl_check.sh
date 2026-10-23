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

# key value (bad)   value (good)   value (stock: what Ubuntu 24.04 ships)
settings='
kernel/kptr_restrict                        0 2 1
kernel/dmesg_restrict                       0 1 1
kernel/yama/ptrace_scope                    0 1 1
kernel/randomize_va_space                   0 2 2
kernel/sysrq                                1 176 176
kernel/unprivileged_bpf_disabled            0 2 2
kernel/perf_event_paranoid                  1 3 4
kernel/ctrl-alt-del                         1 0 0
net/core/bpf_jit_harden                     0 2 0
dev/tty/ldisc_autoload                      1 0 0
fs/suid_dumpable                            1 0 2
fs/protected_hardlinks                      0 1 1
fs/protected_symlinks                       0 1 1
fs/protected_fifos                          0 2 1
fs/protected_regular                        0 2 2
net/ipv4/conf/all/send_redirects            1 0 0
net/ipv4/conf/default/send_redirects        1 0 0
net/ipv4/icmp_ignore_bogus_error_responses  0 1 1
net/ipv4/tcp_timestamps                     2 1 1
net/ipv6/conf/all/accept_redirects          1 0 0
net/ipv6/conf/default/accept_redirects      1 0 0
net/ipv6/conf/all/accept_source_route       1 0 0
net/ipv6/conf/default/accept_source_route   1 0 0
'
expected="lin020w lin021w lin022w lin023f lin024w lin025w lin026w lin027w lin028f lin029f lin030w lin031w lin032w lin033w lin034w lin035f lin036w lin049w lin050w"

build()
{
  # $1 = tree, $2 = column (2 bad, 3 good, 4 stock)
  echo "$settings" | while read key bad good stock
  do
    [ -z "$key" ] && continue
    mkdir -p "$1/proc/sys/`dirname $key`"
    case "$2" in 2) echo "$bad" ;; 3) echo "$good" ;; *) echo "$stock" ;; esac > "$1/proc/sys/$key"
  done
  # the kernel's CPU vulnerability verdicts
  mkdir -p "$1/sys/devices/system/cpu/vulnerabilities"
  echo "Not affected" > "$1/sys/devices/system/cpu/vulnerabilities/meltdown"
  echo "Mitigation: Retpolines; IBPB: conditional" > "$1/sys/devices/system/cpu/vulnerabilities/spectre_v2"
  if [ "$2" = 2 ]; then echo "Vulnerable: No microcode"; else echo "Mitigation: Clear CPU buffers"; fi > "$1/sys/devices/system/cpu/vulnerabilities/mds"
}

run()
{
  # $1 = tree. The setting goes in the copy's tigris.conf, which config exports
  echo "Tigris_Sysctl_Root='$1'" >> "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR=$W sh systems/Linux/2/check_sysctl 2>&1 )
  sed -i '$d' "$W/tigris.conf"
}
runinfo()
{
  # the same, with INFO shown: "--LEVEL-- [id] text" one finding a line
  echo "Tigris_Show_INFO_Msgs=Y" >> "$W/tigris.conf"
  run "$1" | awk '/^--/ { if (l != "") print l; l = $0; next } /^[ \t]/ { sub(/^[ \t]+/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' | tr -s ' '
  sed -i '$d' "$W/tigris.conf"
}
ids()  # ids FILE: the finding ids in a run's output, sorted, one line
{
  grep -o '^--[A-Z]*-- \[[a-z0-9]*\]' "$1" | sed 's/.*\[//; s/\]//' | sort -u | tr '\n' ' ' | sed 's/ $//'
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

# The values every distribution ships are no weakness; the stricter ones
# the documentation offers are INFO, once per key, and only where the key
# has no WARN already. Stock Ubuntu 24.04: kptr_restrict 1, suid_dumpable
# 2, protected_fifos 1 (procps' sysctl.d, systemd's 50-coredump.conf),
# protected_regular 2, ldisc_autoload 0 (its kernel), bpf_jit_harden 0.
build "$W/stock" 4
runinfo "$W/stock" > "$W/stock.out"
[ "`ids "$W/stock.out"`" = "lin043i lin044i lin045i lin047i" ] &&
  ok "stock Ubuntu: nothing above INFO; kptr_restrict 1, suid_dumpable 2, protected_fifos 1 and bpf_jit_harden 0 noted (lin043i lin044i lin045i lin047i), protected_regular 2 and ldisc_autoload 0 not" ||
  bad "stock Ubuntu gave: `ids "$W/stock.out"`"
grep -q '^--INFO-- \[lin044i\] fs.suid_dumpable is 2: setuid programs dump core' "$W/stock.out" && ok "lin044i names the key and value" || bad "lin044i text"
echo 1 > "$W/stock/proc/sys/dev/tty/ldisc_autoload"
echo 1 > "$W/stock/proc/sys/fs/protected_regular"
runinfo "$W/stock" > "$W/stock2.out"
[ "`ids "$W/stock2.out"`" = "lin043i lin044i lin045i lin046i lin047i lin048i" ] &&
  ok "the kernel's ldisc_autoload 1 and systemd's protected_regular 1 (Fedora, Arch): lin048i and lin046i, at INFO" || bad "Fedora-like gave: `ids "$W/stock2.out"`"
echo 0 > "$W/stock/proc/sys/kernel/kptr_restrict"
runinfo "$W/stock" > "$W/stock3.out"
grep -q '\[lin020w\]' "$W/stock3.out" && ! grep -q '\[lin043i\]' "$W/stock3.out" &&
  ok "kptr_restrict 0: lin020w alone, not the INFO about 2 as well" || bad "kptr_restrict 0 gave: `ids "$W/stock3.out"`"

# kernel.sysrq is a bitmask: 1 is everything, and a mask with 8
# (debugging dumps) or 64 (signalling every process) is as bad; the
# distributions' subsets (Ubuntu 176, Debian 438, systemd 16) are fine
for v in 10 64 200 1
do
  echo "$v" > "$W/stock/proc/sys/kernel/sysrq"
  run "$W/stock" | grep -q '\[lin024w\]' && ok "kernel.sysrq $v: lin024w" || bad "kernel.sysrq $v: no lin024w"
done
for v in 176 438 16 0
do
  echo "$v" > "$W/stock/proc/sys/kernel/sysrq"
  run "$W/stock" | grep -q '\[lin024w\]' && bad "kernel.sysrq $v: lin024w" || ok "kernel.sysrq $v: a distribution's mask, nothing"
done

# An offline root (TIGRIS_ROOT, as tigris --root sets it): no /proc/sys of
# its own, so the settings it applies at boot, from its sysctl.d files the
# way systemd-sysctl layers them, for check_sysctl and check_network_config
R=$W/img
mkdir -p "$R/etc/sysctl.d" "$R/usr/lib/sysctl.d"
printf 'net.ipv4.ip_forward = 1\nkernel/sysrq=1\n' > "$R/usr/lib/sysctl.d/50-vendor.conf"
printf 'net.ipv4.ip_forward=0\n' > "$R/etc/sysctl.d/50-vendor.conf"
printf -- '-net.ipv4.conf.*.accept_redirects = 1\n; a comment\nkernel.randomize_va_space = 1\nnet.ipv4.tcp_timestamps = 2\nfs.suid_dumpable = 2\n' > "$R/etc/sysctl.d/60-local.conf"
printf 'kernel.dmesg_restrict = 0\n' > "$R/etc/sysctl.conf"
echo "Tigris_Show_INFO_Msgs=Y" >> "$W/tigris.conf"
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
has '--WARN-- [lin050w] net.ipv4.tcp_timestamps is 2 (set in /etc/sysctl.d/60-local.conf)' && ok "offline root: tcp_timestamps 2 from its sysctl.d: lin050w" || bad "offline lin050w"
has '--INFO-- [lin044i] fs.suid_dumpable is 2 (set in /etc/sysctl.d/60-local.conf)' && ! has '[lin027w]' &&
  ok "offline root: suid_dumpable 2 is the INFO, not the WARN" || bad "offline lin044i"

[ $fail -eq 0 ] && echo "PASS" || { echo "--- bad.out"; cat "$W/bad.out"; echo "--- root.out"; cat "$W/root.out"; }
exit $fail
