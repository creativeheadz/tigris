#!/bin/sh
#
# tests/offline_exports_check.sh - the NFS exports check on an offline root
#
# Builds a root with exports and bootparams that are wrong in known
# ways and runs tigris --root on it with the check on: an anonymous
# uid 0 with write access, world exports both kinds, the root and /usr
# filesystems exported, and root access for a diskless client versus a
# stranger. The root's hostname differs from this host's, so the
# diskless match proves the host list came from the root. NIS is never
# consulted for a root.
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
mkdir -p "$R/etc" "$R/export/root" "$R/export/plain"
printf 'root:x:0:0:root:/root:/bin/bash\nmilo:x:%s:%s:Milo:/home/milo:/bin/bash\n' "$U" "$G" > "$R/etc/passwd"
printf 'root:x:0:\ncrew:x:%s:\n' "$G" > "$R/etc/group"
printf 'nfsrootimg\n' > "$R/etc/hostname"
cat > "$R/etc/exports" <<'EOF'
/data (rw,anon=0)
/pub (ro)
/pub2 (rw)
/ (ro)
/usr (rw)
/export/root (root=diskless1)
/export/plain (root=stranger)
/ (ro,root=diskless1)
EOF
printf 'diskless1 root=nfsrootimg:/export/root\n' > "$R/etc/bootparams"
[ "$uid" = 0 ] && chown -R "$U:$G" "$R"

{
  sed -n 's/^\(Tiger_Check_[A-Z_]*\)=.*/\1=N/p' "$W/tigerrc"
  echo 'Tiger_Check_EXPORTS=Y'
} > "$W/profiles/exports"
chmod 644 "$W/profiles/exports"

( cd "$W" && sh ./tigris -q --profile exports --root "$R" ) > "$W/out" 2>&1
json=`ls "$W"/log/*.jsonl 2>/dev/null | head -1`
[ -n "$json" ] || { echo "FAIL no report:"; cat "$W/out"; exit 1; }
has() { grep -q -- "$1" "$json"; }

has '"id":"nfs001f".*Anonymous ID == 0, for R/W filesystem /data' &&
  ok "anonymous uid 0 with write: nfs001f" || bad "nfs001f"
has '"id":"nfs007w".*Directory /pub exported R/O to everyone' &&
  ok "a world export read-only: nfs007w" || bad "nfs007w"
has '"id":"nfs006f".*Directory /pub2 exported R/W to everyone' &&
  ok "a world export read-write: nfs006f" || bad "nfs006f"
has '"id":"nfs005f".*Exporting the root filesystem (/) R/O to everyone' &&
  ok "the root filesystem to everyone: nfs005f" || bad "nfs005f"
has '"id":"nfs014w".*Exporting the /usr filesystem R/W' &&
  ok "/usr exported read-write: nfs014w" || bad "nfs014w"
has '"id":"nfs012w".*Unprotected directory /export/root is exported with root access for diskless client diskless1' &&
  ok "root access for a diskless client, matched by the root's hostname: nfs012w" || bad "nfs012w"
has '"id":"nfs011w".*Unprotected directory /export/plain is exported with root access to host(s) stranger' &&
  ok "root access for a stranger: nfs011w" || bad "nfs011w"
has '"id":"nfs008f".*Exporting the root filesystem (/) R/O with root access' &&
  ok "the root filesystem with root access: nfs008f" || bad "nfs008f"
grep '"type":"finding"' "$json" | grep -q "$R" && bad "a finding names the root's directory on this host" ||
  ok "findings name the root's own paths, never where it is on this host"
sh "$W/tests/schema_check.sh" "$json" > "$W/schema.out" 2>&1 && ok "the report validates" ||
  { grep -q SKIP "$W/schema.out" && ok "(schema not checked: $(cat "$W/schema.out"))" || { bad "schema"; cat "$W/schema.out"; }; }

[ $fail -eq 0 ] && echo "PASS" || { echo "--- findings"; grep '"type":"finding"' "$json" | cut -c1-220; }
exit $fail
