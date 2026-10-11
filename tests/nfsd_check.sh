#!/bin/sh
#
# tests/nfsd_check.sh - check_nfsd against fixtures of its own
#
# rpcinfo output and nfsd threads are fixture files (Tiger_RPCInfo_Cmd
# and Tiger_ProcDir), /etc/exports comes from a root of its own
# (Tiger_Sysctl_Root, as tigris --root sets it): a daemon serving with
# nothing exported (nfs015w), serving with exports (nothing), nothing
# serving with exports and idle threads (nfs016i), the same with
# running threads (an NFSv4-only server: nothing), and an rpcinfo that
# fails (nothing can be said either way: nothing). Runs as a user and
# as root; nothing here needs privilege.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
cp "$W/tigerrc" "$W/tigerrc.base"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run() {  # run CMD THREADS: check_nfsd with this rpcinfo command and threads
  cp "$W/tigerrc.base" "$W/tigerrc"
  { echo "Tiger_Sysctl_Root='$W/root'"; echo "Tiger_RPCInfo_Cmd='$1'"; echo "Tiger_ProcDir='$W/proc'"; echo "Tiger_Show_INFO_Msgs=Y"; } >> "$W/tigerrc"
  printf '%s' "$2" > "$W/proc/fs/nfsd/threads"
  ( cd "$W" && TIGERHOMEDIR=$W sh ./scripts/check_nfsd ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out" || true
}
has() { grep -F -q -- "$1" "$W/out"; }

mkdir -p "$W/root/etc" "$W/proc/fs/nfsd"
cat > "$W/rpc-nfs" <<'EOF'
   program vers proto   port  service
    100000    4   tcp    111  portmapper
    100003    4   tcp   2049  nfs
    100005    3   udp    892  mountd
EOF
cat > "$W/rpc-plain" <<'EOF'
   program vers proto   port  service
    100000    4   tcp    111  portmapper
EOF
printf '# nothing exported\n' > "$W/root/etc/exports"

run "cat $W/rpc-nfs" 0
has "[nfs015w] NFS serves clients (rpcinfo registers nfs) but /etc/exports exports nothing:" &&
  ok "serving with empty exports: nfs015w" || { bad "serving idle"; cat "$W/out"; }

printf '/data *(ro)\n' > "$W/root/etc/exports"
run "cat $W/rpc-nfs" 0
[ -s "$W/out" ] && { bad "serving with exports"; cat "$W/out"; } || ok "serving with exports: nothing"

run "cat $W/rpc-plain" 0
has "[nfs016i] Exports are configured in /etc/exports but no NFS daemon answers (" &&
  ok "exports with idle threads: nfs016i" || { bad "dead config"; cat "$W/out"; }

run "cat $W/rpc-plain" 8
[ -s "$W/out" ] && { bad "v4-only"; cat "$W/out"; } || ok "exports with running threads (NFSv4-only): nothing"

run false 0
[ -s "$W/out" ] && { bad "rpcinfo silent"; cat "$W/out"; } || ok "an rpcinfo that fails says nothing either way"

grep -q "$W" "$W/out" 2>/dev/null && bad "a finding names where a fixture is on this host" || ok "findings name no fixture paths"

# Without Tiger_RPCInfo_Cmd the check looks for rpcinfo itself. It once
# called a helper it did not define, so on a live system it never ran;
# the "not found" went to /dev/null. The lookup must work now.
cp "$W/tigerrc.base" "$W/tigerrc"
{ echo "Tiger_Sysctl_Root='$W/root'"; echo "Tiger_ProcDir='$W/proc'"; } >> "$W/tigerrc"
( cd "$W" && TIGERHOMEDIR=$W sh ./scripts/check_nfsd ) > /dev/null 2> "$W/err"
grep -q 'not found' "$W/err" && { bad "check_nfsd's own rpcinfo lookup fails:"; cat "$W/err"; } ||
  ok "check_nfsd looks for rpcinfo itself without an error"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
