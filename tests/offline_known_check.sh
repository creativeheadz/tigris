#!/bin/sh
#
# tests/offline_known_check.sh - the intrusion-signs check on an offline root
#
# Builds a root with intrusions planted in known places and runs
# tigris --root on it with the check on: a shell in inetd.conf, a
# trojan path, a plain file where only sockets belong, junk in two
# lost+found directories, BACKDOOR in /bin/login, and a mail spool
# file owned by somebody else. The promiscuous and setuid probes read
# the running system, so they must stay quiet, never fail. As root a
# second spool file belongs to no user at all.
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

R=$W/img
U=$uid; G=`id -g`
[ "$uid" = 0 ] && { U=4242; G=4242; }
mkdir -p "$R/etc" "$R/tmp/.X11-unix" "$R/lost+found" "$R/var/lost+found" "$R/bin" "$R/var/spool/mail"
printf 'root:x:0:0:root:/root:/bin/bash\nmilo:x:%s:%s:Milo:/home/milo:/bin/bash\n' "$U" "$G" > "$R/etc/passwd"
printf 'root:!:19000:0:99999:7:::\nmilo:*:19000:0:99999:7:::\n' > "$R/etc/shadow"
printf 'root:x:0:\ncrew:x:%s:\n' "$G" > "$R/etc/group"
printf '/bin/sh\n/bin/bash\n' > "$R/etc/shells"
printf 'shell stream tcp nowait root /bin/sh sh\n' > "$R/etc/inetd.conf"
echo planted > "$R/tmp/a"
echo not-a-socket > "$R/tmp/.X11-unix/X0"
echo junk > "$R/lost+found/junk"
echo fsck > "$R/lost+found/#123"
echo leftover > "$R/var/lost+found/leftover"
printf 'login.BACKDOOR.binary\n' > "$R/bin/login"
echo mail > "$R/var/spool/mail/alice"
if [ "$uid" = 0 ]; then
  chown -R "$U:$G" "$R"
  echo mail > "$R/var/spool/mail/zed"; chown 9999:9999 "$R/var/spool/mail/zed"
fi

{
  sed -n 's/^\(Tiger_Check_[A-Z_]*\)=.*/\1=N/p' "$W/tigerrc"
  echo 'Tiger_Check_KNOWN=Y'
} > "$W/profiles/known"
chmod 644 "$W/profiles/known"

( cd "$W" && sh ./tigris -q --profile known --root "$R" ) > "$W/out" 2>&1
json=`ls "$W"/log/*.jsonl 2>/dev/null | head -1`
[ -n "$json" ] || { echo "FAIL no report:"; cat "$W/out"; exit 1; }
has() { grep -q -- "$1" "$json"; }

has '"id":"kis014a".*There is a shell defined in inetd.conf' &&
  ok "a shell in the root's inetd.conf: kis014a" || bad "kis014a"
has '"id":"kis002a".*/tmp/a is not zero-length' &&
  ok "a trojan path: kis002a" || bad "kis002a"
has '"id":"kis003a".*/tmp/.X11-unix contains files other than window server sockets' &&
  ok "a plain file among the sockets: kis003a" || bad "kis003a"
has '"id":"kis004w".*/lost+found contains possible non-fsck files' &&
  ok "junk in /lost+found: kis004w" || bad "kis004w root"
has '"id":"kis004w".*/var/lost+found contains possible non-fsck files' &&
  ok "junk in a top-level lost+found: kis004w" || bad "kis004w var"
has '"id":"kis005a".*/bin/login may contain backdoor login' &&
  ok "BACKDOOR in /bin/login: kis005a" || bad "kis005a"
has '"id":"kis008w".*owned by \\"milo\\"' &&
  ok "a spool file owned by somebody else, named from the root's passwd: kis008w" || bad "kis008w"
if [ "$uid" = 0 ]; then
  has '"id":"kis010w"' &&
    ok "a spool file owned by no user: kis010w" || bad "kis010w"
fi
grep '"type":"finding"' "$json" | grep -q 'kis013a\|kis007a' &&
  bad "a live probe spoke on an offline root" ||
  ok "the promiscuous and setuid probes stay quiet"
grep '"type":"finding"' "$json" | grep -q "$R" && bad "a finding names the root's directory on this host" ||
  ok "findings name the root's own paths, never where it is on this host"
sh "$W/tests/schema_check.sh" "$json" > "$W/schema.out" 2>&1 && ok "the report validates" ||
  { grep -q SKIP "$W/schema.out" && ok "(schema not checked: $(cat "$W/schema.out"))" || { bad "schema"; cat "$W/schema.out"; }; }

[ $fail -eq 0 ] && echo "PASS" || { echo "--- findings"; grep '"type":"finding"' "$json" | cut -c1-220; }
exit $fail
