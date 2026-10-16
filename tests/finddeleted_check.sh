#!/bin/sh
#
# tests/finddeleted_check.sh - what check_finddeleted makes of lsof's output (kis012w)
#
# memfd files are anonymous memory, unlinked by design, so lsof always
# marks them "(deleted)"; a desktop browser holds thousands. They are
# not deleted files in use: they must not make kis012w, and they must
# not reach the per-process probes (two lsof calls each), which is what
# took a full run to hours. A stand-in lsof prints two memfd lines and
# one genuinely deleted library; a stand-in ps answers the parent
# queries; every lsof call is logged.
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

cat > "$W/listing" <<'EOF'
brave        62557                                 alice   36u      REG                0,1        2312       9218 /memfd:pipewire-memfd:flags=0x0000000f,type=2,size=2312 (deleted)
Xorg          1274                                  root   27u      REG                0,1     2379776       7189 /memfd:/.nvidia_drv.XXXXXX (deleted)
apache2        1234                              www-data   12u      REG                8,1      123456      67890 /usr/lib/x86_64-linux-gnu/libfoo.so.1 (deleted)
EOF
cat > "$W/lsof" <<'EOF'
#!/bin/sh
echo "$*" >> "$CALLS"
case "$*" in
*-np*) exit 0 ;;   # per-process LISTEN probe: nothing listens here
*) cat "$FIXTURE" ;;
esac
EOF
cat > "$W/ps" <<'EOF'
#!/bin/sh
case "$*" in
*ppid*) echo "99999 1" ;;
*) echo "1 init" ;;
esac
EOF
cat > "$W/drive.sh" <<'EOF'
basedir=$TIGERHOMEDIR
. $basedir/config
LSOF="$LSTUB" PS="$PSTUB" Tiger_Output_Width=0
export LSOF PS Tiger_Output_Width
sh $BASEDIR/scripts/check_finddeleted
EOF
chmod +x "$W/lsof" "$W/ps"
: > "$W/calls"
( cd "$W" && TIGERHOMEDIR=$W LSTUB="$W/lsof" PSTUB="$W/ps" FIXTURE="$W/listing" CALLS="$W/calls" sh ./drive.sh ) > "$W/out" 2>&1

grep -q '\[kis012w\].*libfoo' "$W/out" &&
  ok "a genuinely deleted library: kis012w" || { bad "the deleted library was not reported"; cat "$W/out"; }
grep -q 'memfd' "$W/out" &&
  { bad "a memfd file was reported"; grep 'memfd' "$W/out"; } || ok "the two memfd files: not reported"
n=`grep -c '\-np' "$W/calls"`
[ "$n" -eq 2 ] &&
  ok "two per-process probes, for the deleted file's pid and its parent" || { bad "$n per-process probes instead of 2"; cat "$W/calls"; }
grep -q '62557\|1274' "$W/calls" &&
  { bad "a memfd pid was probed"; cat "$W/calls"; } || ok "no memfd pid was probed"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
