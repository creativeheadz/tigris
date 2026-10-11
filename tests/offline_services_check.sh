#!/bin/sh
#
# tests/offline_services_check.sh - the services and aliases checks on an offline root
#
# Builds a root with a services file and mail aliases that are wrong in
# known ways and runs tigris --root on it with both checks on: two
# services sharing a port, an unknown local service, a uudecode program
# alias, a world-writable handler, a program that is not there, an
# include file with a nested program alias, and an alias through an
# absolute symlink that must resolve inside the root (this host has no
# /linkprog, so the finding proves it). Owners are named from the
# root's passwd. inet002f is not covered: that leg matches the port
# against itself, so it cannot fire on either side.
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
mkdir -p "$R/etc" "$R/etc/mail" "$R/usr/bin" "$R/opt"
printf 'root:x:0:0:root:/root:/bin/bash\nmilo:x:%s:%s:Milo:/home/milo:/bin/bash\n' "$U" "$G" > "$R/etc/passwd"
printf 'root:x:0:\ncrew:x:%s:\n' "$G" > "$R/etc/group"
cat > "$R/etc/services" <<'EOF'
foosvc 49991/tcp
barsvc 49991/tcp
zzlocal 49992/tcp
EOF
cat > "$R/etc/aliases" <<'EOF'
evil: "|/usr/bin/uudecode"
pipe: "|/opt/handler"
ghost: "|/nonexistent/prog"
list: :include:/etc/mail/list
linked: "|/linkprog"
EOF
printf '#!/bin/sh\nexec /bin/false\n' > "$R/usr/bin/uudecode"; chmod 755 "$R/usr/bin/uudecode"
printf '#!/bin/sh\n:\n' > "$R/opt/handler"; chmod 777 "$R/opt/handler"
printf '|/opt/handler\n' > "$R/etc/mail/list"; chmod 664 "$R/etc/mail/list"
ln -s /opt/handler "$R/linkprog"
[ "$uid" = 0 ] && chown -R "$U:$G" "$R" && chown -h "$U:$G" "$R/linkprog"

{
  sed -n 's/^\(Tiger_Check_[A-Z_]*\)=.*/\1=N/p' "$W/tigerrc"
  for c in SERVICES ALIASES; do echo "Tiger_Check_$c=Y"; done
} > "$W/profiles/netsvc"
chmod 644 "$W/profiles/netsvc"

( cd "$W" && sh ./tigris -q --profile netsvc --root "$R" ) > "$W/out" 2>&1
json=`ls "$W"/log/*.jsonl 2>/dev/null | head -1`
[ -n "$json" ] || { echo "FAIL no report:"; cat "$W/out"; exit 1; }
has() { grep -q -- "$1" "$json"; }

has '"id":"inet003w".*The port 49991/tcp is assigned to service barsvc and also to service foosvc' &&
  ok "two services sharing a port: inet003w" || bad "inet003w"
has '"id":"inet004i".*zzlocal is 49992/tcp (local addition)' &&
  ok "an unknown local service: inet004i" || bad "inet004i"
has '"id":"ali002f".*Program alias .evil. executes /usr/bin/uudecode' &&
  ok "a uudecode program alias: ali002f" || bad "ali002f"
has '"id":"ali005w".*Alias .pipe. contains a program entry' &&
  ok "a program alias: ali005w" || bad "ali005w"
has '"id":"ali001i".*Program alias .ghost. executable does not exist' &&
  ok "a program that is not there: ali001i" || bad "ali001i"
has '"id":"ali005w".*Alias .list. contains a program entry (from included file /etc/mail/list)' &&
  ok "a nested program alias in the include file" || bad "ali005w nested"
has '"id":"ali005w".*Alias .linked. contains a program entry' &&
  ok "an alias through an absolute symlink, resolved inside the root" || bad "ali005w symlink"
has '"id":"ali003w".*not owned by root (owned by milo)' &&
  ok "owners named from the root's passwd: ali003w" || bad "ali003w"
has '"id":"ali004f"' &&
  ok "a world-writable handler: ali004f" || bad "ali004f"
has '"id":"ali008i"' &&
  ok "a group-writable include file: ali008i" || bad "ali008i"
grep '"type":"finding"' "$json" | grep -q "$R" && bad "a finding names the root's directory on this host" ||
  ok "findings name the root's own paths, never where it is on this host"
sh "$W/tests/schema_check.sh" "$json" > "$W/schema.out" 2>&1 && ok "the report validates" ||
  { grep -q SKIP "$W/schema.out" && ok "(schema not checked: $(cat "$W/schema.out"))" || { bad "schema"; cat "$W/schema.out"; }; }

[ $fail -eq 0 ] && echo "PASS" || { echo "--- findings"; grep '"type":"finding"' "$json" | cut -c1-220; }
exit $fail
