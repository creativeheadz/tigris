#!/bin/sh
#
# tests/ssh_check.sh - check_ssh against canned sshd -T output
#
# Feeds the check a fixture in which every setting is wrong, then one in
# which every setting is right, through Tiger_SSHD_Cmd. Then an offline
# root (TIGRIS_ROOT, as tigris --root sets it), where sshd is not run and
# the configuration is worked out from the files: an Include whose file
# sets PasswordAuthentication before the main file does (the first value
# wins), Keyword=value, the old ChallengeResponseAuthentication name,
# LoginGraceTime in minutes, a Match block whose settings must not count,
# an included file that is an absolute link inside the root, and defaults
# for what is not set. Needs no root and no sshd.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"

cat > "$W/bad.txt" <<FIX
passwordauthentication yes
permitrootlogin yes
permitemptypasswords yes
x11forwarding yes
maxauthtries 6
usepam no
kbdinteractiveauthentication yes
logingracetime 120
hostbasedauthentication yes
ignorerhosts no
permituserenvironment yes
loglevel quiet
ciphers aes128-cbc,aes256-ctr,3des-cbc
macs hmac-md5,hmac-sha2-256-etm@openssh.com,hmac-sha1-96
kexalgorithms diffie-hellman-group1-sha1,curve25519-sha256
FIX
cat > "$W/good.txt" <<FIX
passwordauthentication no
permitrootlogin prohibit-password
permitemptypasswords no
x11forwarding no
maxauthtries 4
usepam yes
kbdinteractiveauthentication no
logingracetime 60
hostbasedauthentication no
ignorerhosts yes
permituserenvironment no
loglevel verbose
ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
macs hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com
kexalgorithms curve25519-sha256,diffie-hellman-group16-sha512
FIX

run()
{
  echo "Tiger_SSHD_Cmd='cat $1'" >> "$W/tigerrc"
  ( cd "$W" && TIGERHOMEDIR=$W sh scripts/check_ssh 2>&1 )
  sed -i '$d' "$W/tigerrc"
}

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run "$W/bad.txt" > "$W/bad.out"
for code in ssh004w ssh006f ssh007f ssh008w ssh009w ssh010w ssh011w ssh012w ssh013w ssh014w ssh015w ssh016w ssh017w ssh018w ssh019w
do
  if grep -q "\[$code\]" "$W/bad.out"; then echo "ok   $code reported"; else echo "FAIL $code missing"; fail=1; fi
done
# the weak-algorithm messages must name the weak ones and not the good ones
grep -A1 'ssh017w' "$W/bad.out" | tr -d '\n' | grep -q 'aes128-cbc' && ! grep -A1 'ssh017w' "$W/bad.out" | tr -d '\n' | grep -q 'aes256-ctr' \
  && echo "ok   ssh017w names only the weak cipher" || { echo "FAIL ssh017w cipher list"; fail=1; }

run "$W/good.txt" > "$W/good.out"
if grep -q -- '--\(WARN\|FAIL\|ALERT\)--' "$W/good.out"; then
  echo "FAIL good fixture still reported:"; grep -- '--' "$W/good.out" | head; fail=1
else
  echo "ok   nothing reported for the good fixture"
fi

# LoginGraceTime 0 is no limit at all: it must not pass as "under 60"
sed 's/^logingracetime .*/logingracetime 0/' "$W/good.txt" > "$W/zero.txt"
run "$W/zero.txt" > "$W/zero.out"
grep -q 'ssh012w' "$W/zero.out" && grep -q 'logingracetime is 0:' "$W/zero.out" &&
  echo "ok   LoginGraceTime 0 (no limit) is ssh012w" || { echo "FAIL LoginGraceTime 0 passed"; cat "$W/zero.out"; fail=1; }
# An offline root
R=$W/img
mkdir -p "$R/etc/ssh/sshd_config.d" "$R/usr/share/ssh"
cat > "$R/etc/ssh/sshd_config" <<'CONF'
# as Debian ships it: the drop-ins first
Include /etc/ssh/sshd_config.d/*.conf
PasswordAuthentication yes
PermitRootLogin=yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
LoginGraceTime 2m
Ciphers aes256-gcm@openssh.com,aes128-cbc
Match User backup
	PermitEmptyPasswords yes
	MaxAuthTries 10
CONF
echo 'PasswordAuthentication no' > "$R/etc/ssh/sshd_config.d/10-nopass.conf"
# a drop-in that is an absolute link: read inside the root, its LogLevel
# counts; followed on this host it would name nothing
echo 'LogLevel QUIET' > "$R/usr/share/ssh/20-log.conf"
ln -s /usr/share/ssh/20-log.conf "$R/etc/ssh/sshd_config.d/20-log.conf"
echo 'IgnoreRhosts no' > "$R/etc/ssh/sshd_config.d/30-skipped.conf.disabled"
( cd "$W" && TIGRIS_ROOT=$R TIGERHOMEDIR=$W sh scripts/check_ssh 2>&1 ) > "$W/root.out"
codes=`grep -o '\[ssh0[0-9][0-9][a-z]\]' "$W/root.out" | sort -u | tr -d '[]' | tr '\n' ' '`
[ "$codes" = "ssh006f ssh008w ssh009w ssh012w ssh016w ssh017w " ] &&
  ok "offline root: root login, X11, the default MaxAuthTries, LoginGraceTime 2m, the linked drop-in's LogLevel, a CBC cipher; nothing else" || { bad "offline codes: $codes"; cat "$W/root.out"; }
grep -q 'Checking the sshd configuration written in /etc/ssh/sshd_config and its Include files' "$W/root.out" &&
  ok "offline root: says the configuration was read, not asked of sshd" || bad "offline heading"
grep -q 'logingracetime is 120:' "$W/root.out" && grep -q 'maxauthtries is 6:' "$W/root.out" &&
  ok "offline root: 2m is 120 seconds; the Match block's MaxAuthTries 10 does not count, the default 6 does" || { bad "offline values"; cat "$W/root.out"; }
rm "$R/etc/ssh/sshd_config" "$R/etc/ssh/sshd_config.d"/*
( cd "$W" && TIGRIS_ROOT=$R TIGERHOMEDIR=$W sh scripts/check_ssh 2>&1 ) > "$W/none.out"
grep -q -- '--\(WARN\|FAIL\)--' "$W/none.out" && bad "a root without sshd_config: findings" || ok "a root without sshd_config: nothing to say"

[ $fail -eq 0 ] && echo "PASS" || { echo "--- bad.out"; cat "$W/bad.out"; }
exit $fail
