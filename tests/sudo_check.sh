#!/bin/sh
#
# tests/sudo_check.sh - check_sudo against rules and files of its own
#
# The rules are what cvtsudoers -e -f sudoers prints (a desktop's own, captured
# 7 October 2026, then one rule per case), through Tigris_Cvtsudoers_Cmd;
# the files are an /etc/sudoers and sudoers.d under Tigris_Sysctl_Root.
# They belong to whoever runs the test, so the owner is expected to be
# reported unless that is root. Then an offline root (TIGRIS_ROOT, as
# tigris --root sets it), whose sudoers names its drop-ins with
# @includedir, #include and a relative @include: they must be read inside
# the root (one is an absolute link there), leaving out a drop-in with a
# dot in its name, before cvtsudoers sees them, through cat and through
# this host's cvtsudoers when it has one; and openSUSE's /usr/etc/sudoers
# where there is no /etc/sudoers.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
cp "$W/tigris.conf" "$W/tigris.conf.base"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

stub() { { echo '#!/bin/sh'; echo "cat <<'EOT'"; cat; echo 'EOT'; } > "$W/$1"; }
stub desk <<'EOF'
Defaults env_reset
Defaults mail_badpass
Defaults\
    secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin\:/snap/bin
Defaults use_pty
Defaults pwfeedback
root ALL = (ALL : ALL) ALL
%admin ALL = (ALL) ALL
%sudo ALL = (ALL : ALL) ALL
alice ALL = (ALL) NOPASSWD: ALL
ALL ALL = NOPASSWD: /usr/bin/mintdrivers-remove-live-media
ALL ALL = NOPASSWD: /usr/bin/mint-refresh-cache
EOF
stub more <<'EOF'
Defaults:deploy !authenticate
%sudo ALL = (ALL : ALL) ALL
backup ALL = (root) NOPASSWD: /usr/bin/rsync, PASSWD: ALL
ops ALL = (root) /usr/bin/systemctl restart *, !/usr/bin/systemctl restart sshd
web ALL = (www-data) NOPASSWD: /usr/bin/php /srv/app/*.php, \
    /usr/bin/kill
%wheel ALL = (ALL) NOPASSWD: ALL
EOF
printf '#!/bin/sh\necho "cvtsudoers: unable to open /etc/sudoers: Permission denied" >&2\nexit 1\n' > "$W/denied"

r="$W/root"; mkdir -p "$r/etc/sudoers.d"
: > "$r/etc/sudoers"; chmod 0440 "$r/etc/sudoers"; chmod 0755 "$r/etc/sudoers.d"
: > "$r/etc/sudoers.d/ops"; chmod 0440 "$r/etc/sudoers.d/ops"
uid=`id -u`
go() {
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { echo "Tigris_Sysctl_Root='$r'"; echo "Tigris_Cvtsudoers_Cmd='sh $W/$1'"; echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_sudo ) 2>&1 |
    awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
    tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out"
}
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -c -- "$1" "$W/out"; }

go desk
has "--WARN-- [sudo001w] alice may run any command as root with sudo, without a password" && [ "`count sudo001w`" = 1 ] &&
  ok "the desktop: NOPASSWD: ALL for alice, and nobody else" || { bad "desk nopasswd"; cat "$W/out"; }
has "--INFO-- [sudo002i] Some commands may be run with sudo without a password. ALL: /usr/bin/mint-refresh-cache; ALL: /usr/bin/mintdrivers-remove-live-media." &&
  ok "the desktop: Mint's NOPASSWD helpers listed in one INFO" || { bad "desk helpers"; cat "$W/out"; }
[ "`count 'sudo00[34]'`" = 0 ] && ok "the desktop: no !authenticate, no wildcard" || { bad "desk extra"; cat "$W/out"; }

go more
has '--WARN-- [sudo003w] sudo asks nobody for a password: "Defaults:deploy !authenticate".' && ok "Defaults !authenticate: sudo003w" || { bad "authenticate"; cat "$W/out"; }
has '[sudo001w] %wheel may run any command as root' && [ "`count 'sudo001w] backup'`" = 0 ] &&
  ok "PASSWD: after NOPASSWD: in one rule puts the password back for ALL" || { bad "passwd tag"; cat "$W/out"; }
has '--WARN-- [sudo004w] ops may run "/usr/bin/systemctl restart *" with sudo' && has 'web may run "/usr/bin/php /srv/app/*.php"' &&
  [ "`count sudo004w`" = 2 ] && ok "wildcards: one sudo004w per command, the negated one left out" || { bad "wildcards"; cat "$W/out"; }
has 'backup: /usr/bin/rsync' && has 'web: /usr/bin/kill' &&
  ok "a continued line: the NOPASSWD tag carries to the next command" || { bad "continuation"; cat "$W/out"; }

if [ "$uid" != 0 ]; then
  has "[sudo005w] \`/etc/sudoers' is owned by uid $uid" && ok "a sudoers file not root's: sudo005w" || { bad "owner"; cat "$W/out"; }
else
  [ "`count sudo005w`" = 0 ] && ok "root's files, mode 0440: no sudo005w" || { bad "owner (root)"; cat "$W/out"; }
fi
chmod 0664 "$r/etc/sudoers.d/ops"
go desk
has "[sudo005w] \`/etc/sudoers.d/ops' is writable by others (-rw-rw-r--" && ok "a group-writable drop-in: sudo005w" || { bad "writable"; cat "$W/out"; }
chmod 0440 "$r/etc/sudoers.d/ops"

go denied
has '--ERROR-- [sudo006e] sudo'"'"'s rules cannot be read' && has 'Permission denied' && ok "cvtsudoers refused: sudo006e" || { bad "denied"; cat "$W/out"; }
rm -f "$r/etc/sudoers"; go desk
[ "`count .`" = 0 ] && ok "no /etc/sudoers (no sudo): nothing said" || { bad "no sudo"; cat "$W/out"; }

# An offline root
R=$W/img; mkdir -p "$R/etc/sudoers.d" "$R/opt"
cat > "$R/etc/sudoers" <<'EOF'
Defaults env_reset
root ALL=(ALL:ALL) ALL
@includedir /etc/sudoers.d
#include /etc/sudoers.extra
@include sudoers.rel
EOF
# an include after a blank, naming a file this host has and the root does
# not: read inside the root (nothing), never handed to cvtsudoers
printf '  @include %s/hostrule\n' "$W" >> "$R/etc/sudoers"
echo 'mallory ALL=(ALL) NOPASSWD: ALL' > "$W/hostrule"
echo 'alice ALL=(ALL) NOPASSWD: ALL' > "$R/etc/sudoers.d/alice"
echo 'bob ALL=(ALL) NOPASSWD: ALL' > "$R/etc/sudoers.d/bob.disabled"
echo 'carol ALL=(root) /usr/bin/journalctl -u *' > "$R/etc/sudoers.extra"
echo 'dave ALL=(ALL) NOPASSWD: ALL' > "$R/opt/dave"
ln -s /opt/dave "$R/etc/sudoers.d/dave"
echo 'Defaults:erin !authenticate' > "$R/etc/sudoers.rel"
chmod 0440 "$R/etc/sudoers" "$R/etc/sudoers.d/alice" "$R/etc/sudoers.d/bob.disabled" "$R/etc/sudoers.extra" "$R/opt/dave" "$R/etc/sudoers.rel"
offline() {
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { [ -n "$1" ] && echo "Tigris_Cvtsudoers_Cmd='$1'"; echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
  ( cd "$W" && TIGRIS_ROOT=$R TIGERHOMEDIR=$W sh ./systems/Linux/2/check_sudo ) 2>&1 |
    awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
    tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out"
}
offline_ok() {
  has '[sudo001w] alice may run any command' && has '[sudo001w] dave may run any command' && [ "`count 'bob may'`" = 0 ] &&
    has 'carol may run "/usr/bin/journalctl -u *"' && has 'sudo asks nobody for a password: "Defaults:erin !authenticate"' &&
    [ "`count mallory`" = 0 ] &&
    ok "offline root, $1: @includedir, #include, a relative @include and a linked drop-in read inside the root; bob.disabled and this host's file left out" ||
    { bad "offline root, $1"; cat "$W/out"; }
}
offline cat
offline_ok "the flattened rules"
if command -v cvtsudoers >/dev/null 2>&1; then
  offline ""
  offline_ok "through this host's cvtsudoers"
fi
if [ "$uid" != 0 ]; then
  has "[sudo005w] \`/etc/sudoers.d/alice' is owned by uid $uid" && has "[sudo005w] \`/etc/sudoers.d/dave' is owned by uid $uid" &&
    ok "offline root: the drop-ins' owners, the linked one's read inside the root, named by the root's paths" || { bad "offline owners"; cat "$W/out"; }
fi
# openSUSE: no /etc/sudoers, the shipped one in /usr/etc, with its own sudoers.d
mkdir -p "$R/usr/etc/sudoers.d"
mv "$R/etc/sudoers" "$R/usr/etc/sudoers"
chmod 0640 "$R/usr/etc/sudoers"; echo '@includedir /usr/etc/sudoers.d' >> "$R/usr/etc/sudoers"; chmod 0440 "$R/usr/etc/sudoers"
echo 'frank ALL=(ALL) NOPASSWD: ALL' > "$R/usr/etc/sudoers.d/frank"
offline cat
has '[sudo001w] frank may run any command' && has '[sudo001w] alice may run any command' &&
  ok "no /etc/sudoers: /usr/etc/sudoers (openSUSE) and both sudoers.d read" || { bad "/usr/etc/sudoers"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
