#!/bin/sh
#
# tests/portable_macos_check.sh - the portable checks, and tiger itself, on macOS
#
# Until October 2026 the macOS config defined none of what tiger and the
# portable checks need: tiger stopped at init001e before running a
# check, and so did check_accounts, check_umask and check_perms (macOS
# has its own check_passwd, check_group and check_crontabs). Here each
# runs with the macOS config (OS=MacOSX) on macOS-shaped roots: the
# accounts in dslocal plists (gen_passwd_sets, also through the dscl
# stub), /etc a link into /private, path_helper setting PATH, launchd
# owning the umask. A clean root stays quiet, a loose one is reported,
# nothing stops at init001e, and check_issue and check_passwdformat say
# they do not apply. Last, a whole tigris --root run. Runs as a user
# and as root.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
uid=`id -u`; gid=`id -g`
[ "$uid" = 0 ] && chown -R 0:0 "$W"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# run CHECK ROOT: the portable CHECK with the macOS config, ROOT the
# audited system, its findings one a line in $W/out
run() {
  ( cd "$W" && OS=MacOSX REV=15.0 ARCH=arm64 TIGERHOMEDIR=$W TIGRIS_ROOT="$2" sh "./scripts/$1" ) > "$W/raw" 2>&1
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' "$W/raw" |
    tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out"
}
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -c -- "$1" "$W/out"; }
noerr() { ! grep -q 'ERROR\|init00\|not found' "$W/raw"; }

# root ROOT: a macOS root as installed: /etc, /var and /tmp links into
# /private, the accounts in dslocal. As a user the files are the
# user's, so the root's passwd and group name that uid and gid root and
# wheel, for the owners check_perms names.
root() {
  r=$1
  mkdir -p "$r/private/etc/ssh" "$r/private/etc/pam.d" "$r/private/var/db/dslocal/nodes/Default/users" "$r/private/var/at/tabs" "$r/private/var/root" "$r/private/tmp" "$r/Users/admin" "$r/bin"
  ln -s private/etc "$r/etc"; ln -s private/var "$r/var"; ln -s private/tmp "$r/tmp"
  cat > "$r/private/etc/passwd" <<'EOF'
##
# User Database
#
# Note that this file is consulted directly only when the system is running
# in single-user mode.  At other times this information is provided by
# Open Directory.
##
nobody:*:-2:-2:Unprivileged User:/var/empty:/usr/bin/false
root:*:0:0:System Administrator:/var/root:/bin/sh
daemon:*:1:1:System Services:/var/root:/usr/bin/false
_www:*:70:70:World Wide Web Server:/Library/WebServer:/usr/bin/false
EOF
  printf '##\n# Group Database\n##\nnogroup:*:-1:\nwheel:*:0:root\nstaff:*:20:root\n' > "$r/private/etc/group"
  cp "$r/private/etc/passwd" "$r/private/etc/master.passwd"; chmod 600 "$r/private/etc/master.passwd"
  printf 'root ALL = (ALL) ALL\n%%admin ALL = (ALL) ALL\n' > "$r/private/etc/sudoers"; chmod 440 "$r/private/etc/sudoers"
  printf '/bin/bash\n/bin/csh\n/bin/sh\n/bin/zsh\n' > "$r/private/etc/shells"
  printf '# System-wide .profile for sh(1)\n\nif [ -x /usr/libexec/path_helper ]; then\n\teval `/usr/libexec/path_helper -s`\nfi\n' > "$r/private/etc/profile"
  printf '# System-wide .login file for csh(1).\n\nif ( -x /usr/libexec/path_helper ) then\n\teval `/usr/libexec/path_helper -c`\nendif\n' > "$r/private/etc/csh.login"
  printf '# System-wide .bashrc file for interactive bash(1) shells.\n' > "$r/private/etc/bashrc"
  printf 'auth sufficient pam_opendirectory.so\n' > "$r/private/etc/pam.d/sudo"; chmod 444 "$r/private/etc/pam.d/sudo"
  printf '#!/bin/sh\n' > "$r/bin/sh"; chmod 555 "$r/bin/sh"
  for u in root admin daemon1; do cp "$TIGER/tests/fixtures/macos/dsusers/$u.plist" "$r/private/var/db/dslocal/nodes/Default/users/"; done
  chmod 750 "$r/Users/admin" "$r/private/var/root"
  chmod 700 "$r/private/var/at/tabs"
  if [ "$uid" = 0 ]; then
    chown -R 0:0 "$r"; chown -R 501:20 "$r/Users/admin"
  else
    sed -i "s/^root:\*:0:0:/root:*:$uid:$gid:/" "$r/private/etc/passwd"
    sed -i "s/^wheel:\*:0:/wheel:*:$gid:/" "$r/private/etc/group"
  fi
}

C=$W/clean; root "$C"
L=$W/loose; root "$L"
# loose: a world-writable home, a disabled account with a crontab, the
# master file readable, sudoers writable, a profile that sets no PATH,
# an insecure umask in bashrc
chmod 777 "$L/Users/admin"
cp "$TIGER/tests/fixtures/macos/dsusers/locked.plist" "$L/private/var/db/dslocal/nodes/Default/users/"
mkdir -p "$L/Users/locked"
printf '0 * * * * /usr/bin/true\n' > "$L/private/var/at/tabs/locked"
chmod 644 "$L/private/etc/master.passwd"; chmod 666 "$L/private/etc/sudoers"
printf '# no path_helper\n' > "$L/private/etc/profile"
printf 'umask 000\n' > "$L/private/etc/bashrc"

#
# gen_passwd_sets: the accounts from dslocal, and live from dscl
#
( cd "$W" && OS=MacOSX TIGERHOMEDIR=$W TIGRIS_ROOT="$L" sh -c '. ./config >/dev/null 2>&1; $GEN_PASSWD_SETS "$WORKDIR/list"; cat `cat "$WORKDIR/list"`' ) > "$W/set" 2>&1
grep -qx 'locked:\*:502:20::/Users/locked:/bin/bash' "$W/set" && grep -qx 'admin:ShadowHash:501:20::/Users/admin:/bin/bash' "$W/set" &&
  ! grep -q '^_www:' "$W/set" &&
  ok "gen_passwd_sets: the root's dslocal users in passwd's fields, DisabledUser locked" || { bad "gen_passwd_sets offline"; cat "$W/set"; }
echo "Tigris_Dscl_Cmd='$W/tests/fixtures/macos/dscl-stub'" >> "$W/tigris.conf"
( cd "$W" && OS=MacOSX TIGERHOMEDIR=$W sh -c '. ./config >/dev/null 2>&1; $GEN_PASSWD_SETS "$WORKDIR/list2"; s=`cat "$WORKDIR/list2"`; cat "$s" "$s.src"' ) > "$W/set" 2>&1
grep -qx 'daemon1:\*:1:1::/var/empty:/usr/bin/false' "$W/set" && grep -qx 'evil:ShadowHash:0:20::/Users/evil:/bin/bash' "$W/set" &&
  grep -qx 'DirectoryService' "$W/set" &&
  ok "gen_passwd_sets: live, from dscl" || { bad "gen_passwd_sets live"; cat "$W/set"; }

#
# check_accounts
#
run check_accounts "$C"
noerr && grep -q 'Checking accounts from DirectoryService' "$W/raw" && [ "`count .`" = 0 ] &&
  ok "check_accounts, clean: DirectoryService's accounts, silent" || { bad "accounts clean"; cat "$W/raw"; }
run check_accounts "$L"
noerr && has "[acc006w] Login ID admin's home directory (/Users/admin) has" && has "world write access." &&
  has "[acc026w] Login ID admin's home directory (/Users/admin) is readable and searchable by everyone" &&
  has "[acc005w] Login ID locked is disabled, but has a 'cron' file or cron entries." &&
  ok "check_accounts: a world-writable home (acc006w, and acc026w as uid 501 is ordinary on macOS); a disabled account's crontab in /var/at/tabs" || { bad "accounts loose"; cat "$W/raw"; }

#
# check_umask: launchd's, not the start-up files'
#
run check_umask "$C"
noerr && [ "`count .`" = 0 ] && ok "check_umask, clean: start-up files without umask are no finding on macOS" || { bad "umask clean"; cat "$W/raw"; }
run check_umask "$L"
noerr && has '[misc022f] The umask setting in /etc/bashrc is insecure' && [ "`count misc021w`" = 0 ] &&
  ok "check_umask: an insecure umask in bashrc is still misc022f" || { bad "umask loose"; cat "$W/raw"; }

#
# check_path: path_helper sets PATH
#
run check_path "$C"
noerr && [ "`count path009w`" = 0 ] && ok "check_path, clean: profile and csh.login run path_helper" || { bad "path clean"; cat "$W/raw"; }
run check_path "$L"
noerr && has '[path009w] /etc/profile does not export an initial setting for PATH.' && [ "`count path009w`" = 1 ] &&
  ok "check_path: a profile without path_helper or PATH: path009w" || { bad "path loose"; cat "$W/raw"; }

#
# check_perms: /private, where /etc points
#
run check_perms "$C"
noerr && [ "`count .`" = 0 ] && ok "check_perms, clean: macOS's database read, silent" || { bad "perms clean"; cat "$W/raw"; }
run check_perms "$L"
noerr && has '[perm001w] /private/etc/master.passwd should not have world read.' &&
  has '[perm001w] /private/etc/sudoers should not have world write.' &&
  ok "check_perms: master.passwd readable, sudoers writable" || { bad "perms loose"; cat "$W/raw"; }

#
# check_issue and check_passwdformat do not apply
#
run check_issue "$C"
noerr && grep -q '/etc/issue is not shown at login on MacOSX: not checked.' "$W/raw" && [ "`count .`" = 0 ] &&
  ok "check_issue: does not apply, says so" || { bad "issue"; cat "$W/raw"; }
run check_passwdformat "$C"
noerr && grep -q "The accounts are DirectoryService's on MacOSX" "$W/raw" && [ "`count .`" = 0 ] &&
  ok "check_passwdformat: does not apply (nobody's uid -2 is no fault), says so" || { bad "passwdformat"; cat "$W/raw"; }

#
# tigris itself, on the clean root
#
{
  sed -n 's/^\(Tigris_Check_[A-Z_]*\)=.*/\1=N/p' "$W/tigris.conf"
  for c in PASSWD GROUP ACCOUNTS CRON USERUMASK PERMS PATH; do echo "Tigris_Check_$c=Y"; done
} > "$W/profiles/mac"
chmod 644 "$W/profiles/mac"
( cd "$W" && OS=MacOSX REV=15.0 ARCH=arm64 sh ./tigris -q --profile mac --root "$C" ) > "$W/raw" 2>&1
report=`ls "$W"/log/security.report.* 2>/dev/null | grep -v '\.jsonl$' | head -1`
warns='0 WARN'
[ -n "$report" ] && ! grep -q 'init00\|--ERROR--\|not found' "$W/raw" "$report" &&
  grep -q 'Beginning security report for .* MacOSX 15.0' "$report" && grep -q 'Performing check of user accounts' "$report" &&
  grep -q 'Checking for correct umask settings' "$report" && grep -q 'Performing check of system file permissions' "$report" &&
  grep -q '# Checking crontabs' "$report" && grep -q "# Summary: 0 ALERT, 0 FAIL, $warns" "$report" &&
  ok "tigris --root with the macOS config: runs its checks, nothing to report, no init001e" || { bad "tigris"; cat "$W/raw" $report; }

#
# check_sysctl (macOS): the forwarding switches, live and at boot
#
# msys CHECK ROOT: the macOS CHECK, ROOT the audited system (empty:
# live, stub commands from the environment), its findings one a line
# in $W/out
msys() {
  ( cd "$W" && OS=MacOSX REV=15.0 ARCH=arm64 TIGERHOMEDIR=$W TIGRIS_ROOT="$2" sh "./systems/MacOSX/default/$1" ) > "$W/raw" 2>&1
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' "$W/raw" |
    tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out"
}
S=$W/sysctl-bad; mkdir -p "$S/etc"
printf '# a root that forwards\nnet.inet.ip.forwarding=1\nnet.inet6.ip6.forwarding=1\nkern.osrelease=24.0.0\n' > "$S/etc/sysctl.conf"
msys check_sysctl "$S"
noerr && has '[sctl006w] net.inet.ip.forwarding is 1 (set in /etc/sysctl.conf)' && has 'net.inet6.ip6.forwarding is 1' &&
  [ "`count .`" = 2 ] &&
  ok "check_sysctl, sysctl.conf: both families forward, attributed" || { bad "sysctl offline"; cat "$W/raw"; }
msys check_sysctl "$C"
noerr && [ "`count .`" = 0 ] && ok "check_sysctl, no sysctl.conf: the defaults are off, silent" || { bad "sysctl unset"; cat "$W/raw"; }
cat > "$W/sysctl-stub" <<'EOF'
#!/bin/sh
cat <<'EOT'
kern.ostype: Darwin
net.inet.ip.forwarding: 0
net.inet6.ip6.forwarding: 1
kern.osrelease: 24.0.0
EOT
EOF
chmod 755 "$W/sysctl-stub"
Tigris_Sysctl_Cmd="sh $W/sysctl-stub"; export Tigris_Sysctl_Cmd
msys check_sysctl ""
noerr && has '[sctl006w] net.inet6.ip6.forwarding is 1' && [ "`count .`" = 1 ] &&
  ok "check_sysctl, live: only the IPv6 switch, nothing else read" || { bad "sysctl live"; cat "$W/raw"; }
unset Tigris_Sysctl_Cmd

#
# check_timesync (macOS): timed and the switch, live
#
cat > "$W/ps-none" <<'EOF'
#!/bin/sh
echo "launchd /sbin/launchd"
EOF
cat > "$W/ps-timed" <<'EOF'
#!/bin/sh
cat <<'EOT'
launchd /sbin/launchd
timed /usr/libexec/timed
EOT
EOF
cat > "$W/ps-two" <<'EOF'
#!/bin/sh
cat <<'EOT'
timed /usr/libexec/timed
ntpd /usr/sbin/ntpd
EOT
EOF
printf '#!/bin/sh\necho "Network Time: On"\n' > "$W/setup-on"
printf '#!/bin/sh\necho "Network Time: Off"\n' > "$W/setup-off"
chmod 755 "$W"/ps-none "$W"/ps-timed "$W"/ps-two "$W"/setup-on "$W"/setup-off
# mgo PS SETUP: check_timesync live, ps and systemsetup stubbed
mgo() {
  Tigris_Ps_Cmd="sh $W/$1"; Tigris_Systemsetup_Cmd="sh $W/$2"
  export Tigris_Ps_Cmd Tigris_Systemsetup_Cmd
  msys check_timesync ""
}
mgo ps-none setup-off
noerr && has '--WARN-- [time001w] No time synchronisation daemon is running (timed, ntpd or chronyd were looked for)' &&
  has 'systemsetup -setusingnetworktime on' && [ "`count .`" = 1 ] &&
  ok "check_timesync, no daemon: time001w, pointing at systemsetup" || { bad "timesync none"; cat "$W/raw"; }
mgo ps-timed setup-on
noerr && [ "`count .`" = 0 ] && ok "check_timesync, timed with the switch on: silent" || { bad "timesync timed"; cat "$W/raw"; }
mgo ps-timed setup-off
noerr && has '[time001w] timed is running, but automatic date and time is off' && [ "`count .`" = 1 ] &&
  ok "check_timesync, timed with the switch off: time001w" || { bad "timesync off"; cat "$W/raw"; }
mgo ps-two setup-on
noerr && has '[time004w]' && has 'Running: ntpd timed.' && [ "`count .`" = 1 ] &&
  ok "check_timesync, two daemons: time004w, naming both" || { bad "timesync two"; cat "$W/raw"; }
msys check_timesync "$C"
noerr && [ "`count .`" = 0 ] && ok "check_timesync, under --root: live state, silent" || { bad "timesync root"; cat "$W/raw"; }
unset Tigris_Ps_Cmd Tigris_Systemsetup_Cmd

[ $fail -eq 0 ] && echo "PASS"
exit $fail
