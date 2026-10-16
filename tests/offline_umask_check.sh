#!/bin/sh
#
# tests/offline_umask_check.sh - the umask checks on an offline root
#
# Three roots, each wrong in a known way, run with the two umask checks
# on. The first has an insecure UMASK in /etc/login.defs (this host's
# is correct, so the finding proves the root's file was read), shell
# start-up files with no umask anywhere, an empty /etc/csh/login.d, no
# dash or bash, and an executable /bin/csh this host does not have: the
# csh warning must fire (the root's /bin was probed) while the dash and
# bash warnings stay silent (this host's /bin was not). The second root
# is a systemd system, so its insecure /etc/init.d/rc must be silently
# skipped; it also has no login.defs and an insecure file dropped in
# /etc/csh/login.d, which must be reported by its own path. The third
# root's common-session lacks pam_umask while this host's has it, with
# bash installed and no umask anywhere: the bash warning must fire.
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
mkdir -p "$R/etc" "$R/bin" "$R/etc/csh/login.d"
printf 'UMASK 000\n' > "$R/etc/login.defs"
printf '# system profile\n' > "$R/etc/profile"
printf '# system bashrc\n' > "$R/etc/bashrc"
printf '# csh login\n' > "$R/etc/csh.login"
printf '#!/bin/sh\n' > "$R/bin/csh"; chmod 755 "$R/bin/csh"

# Second root: systemd runs the init scripts here, so the rc check has
# nothing to look at, however insecure the leftover rc file is.
S=$W/sysd
mkdir -p "$S/etc/init.d" "$S/run/systemd/system" "$S/etc/csh/login.d"
printf 'umask 000\n' > "$S/etc/init.d/rc"
printf 'umask 000\n' > "$S/etc/csh/login.d/00-site"

# Third root: no pam_umask in the session stack, bash installed, and no
# umask set anywhere.
P=$W/pam
mkdir -p "$P/etc/pam.d" "$P/bin" "$P/etc" "$P/etc/init.d"
printf 'umask 000\n' > "$P/etc/init.d/rc"
printf 'UMASK 022\n' > "$P/etc/login.defs"
printf '# session stack without pam_umask\nsession optional pam_unix.so\n' > "$P/etc/pam.d/common-session"
printf '# system profile\n' > "$P/etc/profile"
printf '#!/bin/sh\n' > "$P/bin/bash"; chmod 755 "$P/bin/bash"

{
  sed -n 's/^\(Tigris_Check_[A-Z_]*\)=.*/\1=N/p' "$W/tigris.conf"
  for c in USERUMASK RCUMASK SYSTEM; do echo "Tigris_Check_$c=Y"; done
} > "$W/profiles/umasks"
chmod 644 "$W/profiles/umasks"

( cd "$W" && sh ./tigris -q --profile umasks --root "$R" ) > "$W/out" 2>&1
json=`ls "$W"/log/*.jsonl 2>/dev/null | head -1`
[ -n "$json" ] || { echo "FAIL no report:"; cat "$W/out"; exit 1; }
has() { grep -q -- "$1" "$json"; }

has '"id":"misc022f".*The default umask setting in /etc/login.defs for users is insecure (000)' &&
  ok "an insecure UMASK in the root's /etc/login.defs: misc022f" || bad "misc022f login.defs"
has '"id":"misc021w".*There is no umask definition for the csh/tcsh shell' &&
  ok "csh installed in the root, no umask for it: misc021w" || bad "misc021w csh"
has '"id":"misc019w".*There are no umask settings for init.d scripts' &&
  ok "no rc files in the root: misc019w" || bad "misc019w"
grep '"type":"finding"' "$json" | grep -q 'no umask definition for the bash shell' &&
  bad "a bash warning from this host's /bin/bash" ||
  ok "no bash warning: the root has no bash, this host's is not probed"
grep '"type":"finding"' "$json" | grep -q 'no umask definition for the dash shell' &&
  bad "a dash warning from this host's /bin/dash" ||
  ok "no dash warning: the root has no dash, this host's is not probed"
grep '"type":"finding"' "$json" | grep -q "$R" && bad "a finding names the root's directory on this host" ||
  ok "findings name the root's own paths, never where it is on this host"
sh "$W/tests/schema_check.sh" "$json" > "$W/schema.out" 2>&1 && ok "the report validates" ||
  { grep -q SKIP "$W/schema.out" && ok "(schema not checked: $(cat "$W/schema.out"))" || { bad "schema"; cat "$W/schema.out"; }; }

# Further runs, each a report name apart: report names only resolve a second.
sleep 2
( cd "$W" && sh ./tigris -q --profile umasks --root "$S" ) > "$W/out2" 2>&1
json2=`ls -t "$W"/log/*.jsonl 2>/dev/null | head -1`
[ -n "$json2" ] && [ "$json2" != "$json" ] || { echo "FAIL no second report:"; cat "$W/out2"; exit 1; }
grep '"type":"finding"' "$json2" | grep -q 'misc017f\|misc019w' &&
  bad "the rc check spoke on a systemd root" ||
  ok "on a systemd root the rc check stays silent, by the root's /run"
grep -q '"id":"misc022f".*in /etc/csh/login.d/00-site for users is insecure' "$json2" &&
  ok "the login.d file read from the root, reported by its own path" || bad "misc022f login.d"
grep -q '"id":"misc026w".*no default umask settings for user login shells in /etc/login.defs' "$json2" &&
  ok "no login.defs at all: misc026w" || bad "misc026w"
grep '"type":"finding"' "$json2" | grep -q "$S" && bad "a finding names the second root's directory on this host" ||
  ok "the second report names the root's own paths too"
sh "$W/tests/schema_check.sh" "$json2" > "$W/schema2.out" 2>&1 && ok "the second report validates" ||
  { grep -q SKIP "$W/schema2.out" && ok "(schema not checked: $(cat "$W/schema2.out"))" || { bad "schema2"; cat "$W/schema2.out"; }; }

sleep 2
( cd "$W" && sh ./tigris -q --profile umasks --root "$P" ) > "$W/out3" 2>&1
json3=`ls -t "$W"/log/*.jsonl 2>/dev/null | head -1`
[ -n "$json3" ] && [ "$json3" != "$json2" ] || { echo "FAIL no third report:"; cat "$W/out3"; exit 1; }
grep -q '"id":"misc021w".*There is no umask definition for the bash shell' "$json3" &&
  ok "bash installed, no umask, no pam_umask: misc021w" || bad "misc021w bash"
grep -q '"id":"misc017f".*The umask setting in /etc/init.d/rc for the init scripts is insecure' "$json3" &&
  ok "an insecure umask in the root's /etc/init.d/rc: misc017f" || bad "misc017f"
grep '"type":"finding"' "$json3" | grep -q "$P" && bad "a finding names the third root's directory on this host" ||
  ok "the third report names the root's own paths too"
sh "$W/tests/schema_check.sh" "$json3" > "$W/schema3.out" 2>&1 && ok "the third report validates" ||
  { grep -q SKIP "$W/schema3.out" && ok "(schema not checked: $(cat "$W/schema3.out"))" || { bad "schema3"; cat "$W/schema3.out"; }; }

[ $fail -eq 0 ] && echo "PASS" || { echo "--- findings"; grep -h '"type":"finding"' "$json" "$json2" "$json3" | cut -c1-220; }
exit $fail
