#!/bin/sh
#
# tests/trust_check.sh - what Tigris trusts: its own files and directories
#
# Tigris runs as root, and runs its own configuration as shell code, so
# what it reads and where it writes must be its own. This plants the
# opposite of each rule and expects Tigris to refuse, saying why, and
# a few of the rules' good cases to pass: a directory it was told to run
# from that another user owns or group may write (init013e); a working
# directory group may write (con018e); an acceptance file group may
# write (con003c, and the finding it would hide is reported); a cronrc
# group may write (tig001e); a temporary file's name taken by a dangling
# link (init009e); a program first on the inherited PATH, which must not
# run (config sets PATH first); and the defaults the README promises
# (the scan looks for setuid, setgid and world-writable directories).
# Needs no root.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
chmod -R go-w "$W"
# as root (CI, a container) the copy keeps the checkout's owner: make it ours
[ "`id -u`" = 0 ] && chown -R 0:0 "$W"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
sed 's/^\(Tiger_\(Check\|Run\|Deb\)_[A-Za-z0-9_]*\)=.*/\1=N/' "$W/tigerrc" > "$W/rc.t"; chmod 600 "$W/rc.t"
run() { ( cd "$W" && sh ./tigris -q -c rc.t "$@" ) > "$W/out" 2>&1; echo $?; }

# the defaults
for v in Setuid Setgid WDIR; do
  grep -q "^Tiger_FSScan_$v=Y" "$W/tigerrc" && ok "Tiger_FSScan_$v=Y by default" || bad "Tiger_FSScan_$v is not Y"
done
grep -q "^Tiger_SSH_Protocol='2'" "$W/tigerrc" && ok "only SSH protocol 2 is acceptable" || bad "Tiger_SSH_Protocol"

# a sane tree runs
st=`run`; [ "$st" = 0 ] && ok "a tree of the runner's, modes 755/644: runs" || { bad "a sane tree: exit $st"; cat "$W/out"; }

# the working directory writable by group: refused on a host; inside a
# container (CI runs these suites in one) it is the host user's bind
# mount, said with con019c and allowed
chmod 775 "$W/run"; st=`run`
if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || [ -f /run/systemd/container ]; then
  [ "$st" = 0 ] && ( cd "$W" && sh ./tigris -c rc.t 2>&1 | grep -q 'con019c' ) && ok "a group-writable working directory, in a container: con019c, and a run" || { bad "group-writable run/ in a container: exit $st"; cat "$W/out"; }
else
  [ "$st" != 0 ] && grep -q 'con018e' "$W/out" && ok "a group-writable working directory: con018e, no run" || { bad "group-writable run/: exit $st"; cat "$W/out"; }
fi
chmod 755 "$W/run"

# the tree itself writable by group
chmod 775 "$W"; st=`run`
[ "$st" != 0 ] && grep -q 'init013e' "$W/out" && ok "a group-writable base directory: init013e, nothing run" || { bad "group-writable base: exit $st"; cat "$W/out"; }
chmod 755 "$W"

# an acceptance file group may write: not read, the finding stays
printf 'acc001w\t-\t*\tnot mine\n' > "$W/tigris.accepted"; chmod 664 "$W/tigris.accepted"
( cd "$W" && TIGERHOMEDIR=$W sh ./config -t ) > "$W/cfg" 2>&1
grep -q 'con003c.*tigris.accepted' "$W/cfg" && ok "a group-writable acceptance file: con003c" || { bad "acceptance file"; head -3 "$W/cfg"; }
rm -f "$W/tigris.accepted"

# a cronrc group may write
chmod 664 "$W/cronrc"
( cd "$W" && TIGERHOMEDIR=$W sh ./tigercron "$W/cronrc" -c rc.t ) > "$W/cron.out" 2>&1
grep -q 'tig001e' "$W/cron.out" && ok "a group-writable cronrc: tig001e, tigercron stops" || { bad "cronrc"; head -3 "$W/cron.out"; }
chmod 644 "$W/cronrc"

# a temporary file's name taken by a dangling link
cat > "$W/st.sh" <<'EOT'
D=$1; cd "$D" || exit 1; TIGERHOMEDIR=$D; export TIGERHOMEDIR; set --
. ./config >/dev/null 2>&1; . ./initdefs
ln -s "$D/victim" "$D/run/tmp.1"
safe_temp "$D/run/tmp.1"
EOT
sh "$W/st.sh" "$W" > "$W/st.out" 2>&1
grep -q 'init009e' "$W/st.out" && [ ! -e "$W/victim" ] && ok "a dangling link where a temporary file goes: init009e, nothing created" || { bad "safe_temp"; cat "$W/st.out"; ls "$W/victim" 2>&1; }

# a program first on the inherited PATH must not run
mkdir -p "$W/shim"; printf '#!/bin/sh\n: > "%s/SHIM_RAN"\nexec /usr/bin/whoami "$@"\n' "$W" > "$W/shim/whoami"; chmod 755 "$W/shim/whoami"
( cd "$W" && PATH="$W/shim:$PATH" TIGERHOMEDIR=$W sh ./config -t ) > /dev/null 2>&1
[ ! -e "$W/SHIM_RAN" ] && ok "a whoami first on the inherited PATH did not run" || bad "the PATH shim ran"

[ $fail -eq 0 ] && echo PASS || echo FAIL
exit $fail
