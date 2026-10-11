#!/bin/sh
#
# tests/ssh_sunos_check.sh - the portable check_ssh on Solaris roots
#
# Solaris 11.4 ships OpenSSH with its sshd_config at
# /etc/ssh/sshd_config, the first path the portable check reads
# off an audited root: no shadow is needed, and writing one would
# fork a grammar that is not ours. These legs prove the portable
# check reads a Solaris root: password logins and a password root
# login fail loud, a tight config is silent. Runs as a user and
# as root; the fixtures read the same for both.
#
TIGER=${TIGER:-`cd "\`dirname \"$0\"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run() {  # run ROOT OUTFILE: check_ssh with ROOT as the audited system
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./scripts/check_ssh ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }
empty() { [ ! -s "$1" ]; }
sshd() {  # sshd ROOT [KEY=VALUE...]: a Solaris sshd_config, stock
  # tight unless a KEY=VALUE restates it (sshd takes the first
  # value of a keyword, so overrides rewrite the stock line)
  r=$1; shift
  mkdir -p "$r/etc/ssh"
  cat > "$r/etc/ssh/sshd_config" <<'EOF'
Protocol 2
PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 3
UsePAM yes
KbdInteractiveAuthentication no
LoginGraceTime 60
HostbasedAuthentication no
IgnoreRhosts yes
PermitUserEnvironment no
LogLevel VERBOSE
EOF
  for kv in "$@"; do case "$kv" in *=*)
    k=${kv%%=*}; v=${kv#*=}
    sed "s/^$k .*/$k $v/" "$r/etc/ssh/sshd_config" > "$r/etc/ssh/sshd_config.new" &&
    mv "$r/etc/ssh/sshd_config.new" "$r/etc/ssh/sshd_config" ;;
  esac; done
}

B=$W/bad; sshd "$B" "PermitRootLogin=yes" "PasswordAuthentication=yes"
run "$B" "$W/out"
has '[ssh006f]' "$W/out" &&
has '[ssh004w]' "$W/out" &&
  ok "password root login, password logins: ssh006f, ssh004w" || { bad "bad"; cat "$W/out"; }

T=$W/tight; sshd "$T"
run "$T" "$W/out"
empty "$W/out" &&
  ok "stock tight Solaris sshd_config: silent" || { bad "tight noisy"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
