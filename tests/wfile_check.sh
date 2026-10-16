#!/bin/sh
#
# tests/wfile_check.sh - world-writable files: the fallback lister and the
# sub-check that judges the list
#
# util/flogit is the path the filesystem scan takes without GNU find's
# -fprintf (busybox): fed a list of files, it must put the regular file
# anyone can write in the wfile list and nothing else there (not the
# world-writable directory, which is wdir's, not a link to the file, not
# a file nobody else can write), and fill no wfile list with
# Tigris_FSScan_WFILE=N. sub/check_wfile, run as find_files runs it
# (config sourced, the list in), must list each file under the prefixes
# Tigris_FSScan_DetailDirs names, with its mode and owner, and count the
# others per directory; '*' lists them all. The one-pass find and the
# offline root are tests/offline_scan_check.sh's.
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

F=$W/fx
mkdir -p "$F/sub" "$F/shared"
: > "$F/open"; : > "$F/sub/deeper"; : > "$F/plain"; : > "$F/exe"
chmod 666 "$F/open" "$F/sub/deeper"; chmod 644 "$F/plain"; chmod 755 "$F/exe"; chmod 777 "$F/shared"
ln -s "$F/open" "$F/lnk"
me=`id -un`

cat > "$W/drive.sh" <<'DRIVE'
basedir=$TIGERHOMEDIR
. $basedir/config
# tigris.conf sets these: the test's values are given after it
CONFIGURED_ALREADY=YES Tigris_Output_Width=0
export CONFIGURED_ALREADY Tigris_Output_Width
[ -n "$DETAIL" ] && { Tigris_FSScan_DetailDirs=$DETAIL; export Tigris_FSScan_DetailDirs; }
[ -n "$WFILE" ] && { Tigris_FSScan_WFILE=$WFILE; export Tigris_FSScan_WFILE; }
case "$KIND" in
  flogit) sh $BASEDIR/util/flogit "$O.suid" "$O.dev" "$O.link" "$O.wdir" "$O.nouser" "$O.nogroup" "$O.test" "$O.sgid" "$O.wfile" < "$INPUT" ;;
  *) sh $BASEDIR/scripts/sub/check_wfile "$INPUT" ;;
esac
DRIVE

# --- flogit
printf '%s\n' "$F/open" "$F/sub/deeper" "$F/plain" "$F/exe" "$F/shared" "$F/lnk" > "$W/list"
rm -f "$W/o".*
( cd "$W" && TIGERHOMEDIR=$W KIND=flogit INPUT=$W/list O=$W/o sh ./drive.sh ) > "$W/out" 2>&1
if [ "`sort "$W/o.wfile" 2>/dev/null`" = "`printf '%s\n' "$F/open" "$F/sub/deeper" | sort`" ]; then
  ok "flogit: the two files anyone can write are in the wfile list, nothing else"
else
  bad "flogit's wfile list:"; cat "$W/o.wfile" 2>/dev/null; cat "$W/out"
fi
grep -qx "$F/shared" "$W/o.wdir" 2>/dev/null && ! grep -q "$F/shared" "$W/o.wfile" &&
  ok "flogit: the world-writable directory is in wdir's list, not wfile's" || bad "flogit: the directory"
grep -qx "$F/lnk" "$W/o.link" 2>/dev/null && ! grep -q "$F/lnk" "$W/o.wfile" &&
  ok "flogit: the link to the file is in link's list, not wfile's" || bad "flogit: the link"
rm -f "$W/o".*
( cd "$W" && TIGERHOMEDIR=$W KIND=flogit INPUT=$W/list O=$W/o WFILE=N sh ./drive.sh ) > "$W/out" 2>&1
[ -s "$W/o.wfile" ] && bad "flogit: Tigris_FSScan_WFILE=N still filled the wfile list" ||
  ok "flogit: Tigris_FSScan_WFILE=N fills no wfile list"

# --- check_wfile
printf '%s\n' "$F/open" "$F/sub/deeper" > "$W/wlist"
go() { ( cd "$W" && TIGERHOMEDIR=$W KIND=check INPUT=$W/wlist DETAIL="$1" sh ./drive.sh ) > "$W/out" 2>&1; }
has() { grep -F -q -- "$1" "$W/out"; }

go /etc
has "--WARN-- [fsys021w] 2 world-writable files under $W are not listed (see Tigris_FSScan_DetailDirs)." && ! has fsys020f &&
  ok "outside the detail directories: counted per directory, not listed" || { bad "counted"; cat "$W/out"; }
go "$F/sub"
has "--FAIL-- [fsys020f] File $F/sub/deeper is world writable (-rw-rw-rw-, owner $me)." && has "Anyone can change its contents." &&
  ok "under a detail directory: listed, with its mode and owner" || { bad "listed under a prefix"; cat "$W/out"; }
has "1 world-writable files under $W are not listed" && ! has "File $F/open " &&
  ok "the one outside it is still counted" || { bad "the other one"; cat "$W/out"; }
go '*'
has "File $F/open is world writable" && has "File $F/sub/deeper is world writable" && ! has fsys021w &&
  ok "'*' lists them all" || { bad "'*'"; cat "$W/out"; }
grep -q "^# Checking for world-writable files" "$W/out" && ok "the check announces itself" || bad "no header"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
