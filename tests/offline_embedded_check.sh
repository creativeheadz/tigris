#!/bin/sh
#
# tests/offline_embedded_check.sh - the embedded-pathnames check on an offline root
#
# Builds a root whose scripts name other paths and runs tigris --root
# on it with the embedded and aliases checks on: a program alias seeds
# its tool, whose strings name a world-writable helper, an executable
# one, and an absolute symlink that must resolve inside the root (this
# host has no /evil-link, so the finding proves it). The seed list
# itself names a profile and an init.d glob, which must expand inside
# the root. Owners are named from the root's passwd.
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
mkdir -p "$R/etc" "$R/etc/init.d" "$R/opt/app" "$R/root"
printf 'root:x:0:0:root:/root:/bin/bash\nmilo:x:%s:%s:Milo:/home/milo:/bin/bash\n' "$U" "$G" > "$R/etc/passwd"
printf 'root:x:0:\ncrew:x:%s:\n' "$G" > "$R/etc/group"
printf 'pipe: "|/opt/app/tool"\n' > "$R/etc/aliases"
cat > "$R/opt/app/tool" <<'EOF'
#!/bin/sh
exec /opt/app/helper --serve
exec /opt/app/helper2 --serve
cat /evil-link
EOF
chmod 755 "$R/opt/app/tool"
printf 'data\n' > "$R/opt/app/helper"; chmod 666 "$R/opt/app/helper"
printf 'data\n' > "$R/opt/app/helper2"; chmod 755 "$R/opt/app/helper2"
printf 'secret\n' > "$R/opt/app/secret"; chmod 600 "$R/opt/app/secret"
ln -s /opt/app/secret "$R/evil-link"
printf 'PATH=/opt/app/helper3:/usr/bin\n' > "$R/root/.profile"
printf 'data\n' > "$R/opt/app/helper3"; chmod 666 "$R/opt/app/helper3"
printf '#!/bin/sh\nDAEMON=/opt/app/helper4\n' > "$R/etc/init.d/svc"; chmod 755 "$R/etc/init.d/svc"
printf 'data\n' > "$R/opt/app/helper4"; chmod 755 "$R/opt/app/helper4"
[ "$uid" = 0 ] && chown -R "$U:$G" "$R" && chown -h "$U:$G" "$R/evil-link"

{
  sed -n 's/^\(Tiger_Check_[A-Z_]*\)=.*/\1=N/p' "$W/tigerrc"
  echo 'Tiger_Embed_Report_Exec_Only=N'
  for c in EMBEDDED ALIASES; do echo "Tiger_Check_$c=Y"; done
} > "$W/profiles/embed"
chmod 644 "$W/profiles/embed"

( cd "$W" && sh ./tigris -q --profile embed --root "$R" ) > "$W/out" 2>&1
json=`ls "$W"/log/*.jsonl 2>/dev/null | head -1`
[ -n "$json" ] || { echo "FAIL no report:"; cat "$W/out"; exit 1; }
has() { grep -q -- "$1" "$json"; }

has '"id":"embed004i".*Path ./opt/app/helper. is group .crew. and world writable' &&
  ok "a world-writable helper, seeded through the alias: embed004i" || bad "embed004i helper"
has '"id":"embed002w".*Path ./opt/app/helper2. is not owned by root (owned by milo)' &&
  ok "an executable helper owned by milo: embed002w" || bad "embed002w helper2"
has '"id":"embed002i".*Path ./evil-link. is not owned by root (owned by milo)' &&
  ok "an absolute symlink resolved inside the root: embed002i" || bad "embed002i symlink"
has '"id":"embed004i".*Path ./opt/app/helper3. is group .crew. and world writable' &&
  ok "a seed from the profile list: embed004i" || bad "embed004i helper3"
has '"id":"embed002w".*Path ./opt/app/helper4. is not owned by root' &&
  ok "a seed from the init.d glob, expanded in the root: embed002w" || bad "embed002w helper4"
grep '"type":"finding"' "$json" | grep -q "$R" && bad "a finding names the root's directory on this host" ||
  ok "findings name the root's own paths, never where it is on this host"
sh "$W/tests/schema_check.sh" "$json" > "$W/schema.out" 2>&1 && ok "the report validates" ||
  { grep -q SKIP "$W/schema.out" && ok "(schema not checked: $(cat "$W/schema.out"))" || { bad "schema"; cat "$W/schema.out"; }; }

[ $fail -eq 0 ] && echo "PASS" || { echo "--- findings"; grep '"type":"finding"' "$json" | cut -c1-220; }
exit $fail
