#!/bin/sh
#
# tests/offline_perms_check.sh - the permissions, devices and logfiles checks on an offline root
#
# Builds a root that is wrong in known ways and runs tigris --root on
# it with the three checks on: an /etc/passwd that is group- and
# world-writable and owned by milo (the database expects root's 644),
# a setuid /bin/login (unexpected) and a setuid /bin/su (expected: it
# must stay silent), a group-writable /bin/aaa that the database's
# /bin/* entry must find inside the root and not on this host, a
# regular file and an unexpected directory in
# /dev, an all-symlinks directory and an expected one that must stay
# silent, a btmp with the wrong mode, and missing wtmp and lastlog.
# Syslog stands in for messages; a second root with only a persistent
# journal must need no text log at all. As root the test also makes
# two device nodes and gives utmp to the utmp group (silence then
# proves the group was named from the root's group file); as a user
# utmp instead carries the wrong mode and is reported.
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
mkdir -p "$R/etc" "$R/bin" "$R/dev/hidedir" "$R/dev/byfoo" "$R/dev/pts" "$R/var/log" "$R/var/run"
printf 'root:x:0:0:root:/root:/bin/bash\nmilo:x:%s:%s:Milo:/home/milo:/bin/bash\n' "$U" "$G" > "$R/etc/passwd"
chmod 666 "$R/etc/passwd"
printf 'root:x:0:\ncrew:x:%s:\nutmp:x:4243:\n' "$G" > "$R/etc/group"
printf '#!/bin/sh\n:\n' > "$R/bin/login"; chmod 4755 "$R/bin/login"
printf '#!/bin/sh\n:\n' > "$R/bin/su"; chmod 4755 "$R/bin/su"
: > "$R/bin/aaa"; chmod 775 "$R/bin/aaa"
: > "$R/bin/bbb"; chmod 775 "$R/bin/bbb"
ln -s aaa "$R/bin/lnk"
mkdir -p "$R/usr" "$R/var/tmp"; chmod 1777 "$R/var/tmp"; ln -s ../var/tmp "$R/usr/tmp"
echo sneaky > "$R/dev/sneaky"
echo hidden > "$R/dev/hidedir/cache"
ln -s ../sneaky "$R/dev/byfoo/alias"
ln -s sneaky "$R/dev/mylink"
: > "$R/var/log/btmp"; chmod 644 "$R/var/log/btmp"
: > "$R/var/log/syslog"; chmod 640 "$R/var/log/syslog"
: > "$R/var/run/utmp"
if [ "$uid" = 0 ]; then
  chown -R "$U:$G" "$R"
  chmod 4755 "$R/bin/login" "$R/bin/su"
  mknod -m 666 "$R/dev/sda" b 8 0
  mknod -m 644 "$R/dev/kmem" c 1 1
  # world-readable on every Linux, by design: no dev004w
  mknod -m 644 "$R/dev/kmsg" c 1 11; mknod -m 644 "$R/dev/autofs" c 10 235
  chown "$U:4243" "$R/var/run/utmp"; chmod 664 "$R/var/run/utmp"
else
  chmod 600 "$R/var/run/utmp"
fi

J=$W/journal
mkdir -p "$J/etc" "$J/var/log/journal/deadbeef"
printf 'root:x:0:0:root:/root:/bin/bash\n' > "$J/etc/passwd"
printf 'root:x:0:\n' > "$J/etc/group"
echo entry > "$J/var/log/journal/deadbeef/system.journal"

{
  sed -n 's/^\(Tiger_Check_[A-Z_]*\)=.*/\1=N/p' "$W/tigerrc"
  for c in PERMS BACKUPS LOGFILES; do echo "Tiger_Check_$c=Y"; done
} > "$W/profiles/perms"
chmod 644 "$W/profiles/perms"

( cd "$W" && sh ./tigris -q --profile perms --root "$R" ) > "$W/out" 2>&1
json=`ls "$W"/log/*.jsonl 2>/dev/null | head -1`
[ -n "$json" ] || { echo "FAIL no report:"; cat "$W/out"; exit 1; }
has() { grep -q -- "$1" "$json"; }

has '"id":"perm014a".*The owner of /etc/passwd should be root (owned by milo)' &&
  ok "passwd owned by milo, named from the root's passwd: perm014a" || bad "perm014a owner"
has '"id":"perm001w".*/etc/passwd should not have world write' &&
  ok "a world-writable passwd: perm001w" || bad "perm001w"
has '"id":"perm023a".*/bin/login is setuid to .milo' &&
  ok "an unexpected setuid: perm023a" || bad "perm023a"
has '"id":"perm023a".*/bin/su is setuid' &&
  bad "the setuid the database expects of /bin/su was reported" || ok "a setuid the database expects (/bin/su) stays silent"
has '"id":"perm001w".*/bin/aaa should not have group write' &&
  ok "the /bin/* entry expands inside the root: perm001w for /bin/aaa" || bad "/bin/* was not expanded inside the root"
has '"id":"perm001w".*/bin/bbb should not have group write' &&
  ok "every match of /bin/* is checked, not only the first: perm001w for /bin/bbb" || bad "/bin/bbb: only the first match was checked"
has '"message":"/bin/lnk ' &&
  bad "a symlink in /bin was checked as what it points to" || ok "a symlink match (/bin/lnk) is skipped, as live"
has '"message":"/usr/tmp ' &&
  bad "/usr/tmp, a link to a sticky /var/tmp, was reported" || ok "a link to a sticky directory (/usr/tmp) stays silent"
has '"id":"dev003w".*File /dev/sneaky is a regular file in a device directory' &&
  ok "a regular file in /dev: dev003w" || bad "dev003w file"
has '"id":"dev003w".*The directory /dev/hidedir resides in a device directory' &&
  ok "an unexpected directory in /dev: dev003w" || bad "dev003w dir"
grep '"type":"finding"' "$json" | grep -q 'byfoo' &&
  bad "the all-symlinks directory reported something" ||
  ok "a directory of nothing but symlinks stays silent"
grep '"type":"finding"' "$json" | grep -q 'mylink' &&
  bad "the symlink reported something" ||
  ok "a symlink in /dev stays silent"
if [ "$uid" = 0 ]; then
  has '"id":"dev002f".*/dev/sda has world permissions' &&
    ok "a world-writable device node: dev002f" || bad "dev002f"
  has '"id":"dev004w".*/dev/kmem is world readable' &&
    ok "a world-readable device node: dev004w" || bad "dev004w"
  { has '"id":"dev004w".*/dev/kmsg is world readable' || has '"id":"dev004w".*/dev/autofs is world readable'; } &&
    bad "kmsg or autofs, world-readable by design, was dev004w" ||
    ok "kmsg and autofs, world-readable on every Linux, stay silent"
  grep '"type":"finding"' "$json" | grep -q 'utmp permission should be' &&
    bad "utmp in the utmp group at 664 reported something" ||
    ok "utmp in the utmp group at 664 is silent, by the root's group file"
else
  has '"id":"logf005f".*Log file /var/run/utmp permission should be 644' &&
    ok "utmp with the wrong mode: logf005f" || bad "logf005f utmp"
fi
has '"id":"logf001f".*Log file /var/log/wtmp does not exist' &&
  ok "no wtmp: logf001f" || bad "logf001f"
has '"id":"logf005f".*Log file /var/log/btmp permission should be 600' &&
  ok "btmp with the wrong mode: logf005f" || bad "logf005f btmp"
has '"id":"logf003f".*Log file /var/log/lastlog does not exist' &&
  ok "no lastlog: logf003f" || bad "logf003f"
grep '"type":"finding"' "$json" | grep -q 'logf007f' &&
  bad "syslog standing in for messages reported something" ||
  ok "syslog stands in for messages, silently"
grep '"type":"finding"' "$json" | grep -q "$R" && bad "a finding names the root's directory on this host" ||
  ok "findings name the root's own paths, never where it is on this host"
sh "$W/tests/schema_check.sh" "$json" > "$W/schema.out" 2>&1 && ok "the report validates" ||
  { grep -q SKIP "$W/schema.out" && ok "(schema not checked: $(cat "$W/schema.out"))" || { bad "schema"; cat "$W/schema.out"; }; }

# Second run, a report name apart: report names only resolve a second.
sleep 2
( cd "$W" && sh ./tigris -q --profile perms --root "$J" ) > "$W/out2" 2>&1
json2=`ls -t "$W"/log/*.jsonl 2>/dev/null | head -1`
[ -n "$json2" ] && [ "$json2" != "$json" ] || { echo "FAIL no second report:"; cat "$W/out2"; exit 1; }
grep -q '"id":"logf001f"' "$json2" &&
  ok "the journal-only root is still audited" || bad "journal run"
grep '"type":"finding"' "$json2" | grep -q 'logf007f' &&
  bad "a persistent journal still wants a text log" ||
  ok "a persistent journal excuses messages and syslog"
grep '"type":"finding"' "$json2" | grep -q "$J" && bad "a finding names the second root's directory on this host" ||
  ok "the second report names the root's own paths too"
sh "$W/tests/schema_check.sh" "$json2" > "$W/schema2.out" 2>&1 && ok "the second report validates" ||
  { grep -q SKIP "$W/schema2.out" && ok "(schema not checked: $(cat "$W/schema2.out"))" || { bad "schema2"; cat "$W/schema2.out"; }; }

[ $fail -eq 0 ] && echo "PASS" || { echo "--- findings"; grep -h '"type":"finding"' "$json" "$json2" | cut -c1-220; }
exit $fail
