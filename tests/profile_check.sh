#!/bin/sh
#
# tests/profile_check.sh - tigris-quick.conf differs from tigris.conf in one line,
# and the profiles are overlays config applies
#
# The quick profile is a full copy of tigris.conf with the filesystem scan
# turned off (an unset Tigris_Check_* means "run", so profiles cannot be
# short). This fails unless the two files' assignments differ only in
# Tigris_Check_FILESYSTEM=Y vs =N. Comments and the header may differ;
# anything else names the setting that drifted.
#
# Normalization assumes values contain no ' #' (true today); the eval'd
# assignment is compared without its eval prefix.
#
TIGER=${TIGER:-`cd "\`dirname \"$0\"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

norm() {
  # assignments only: no full-line comments, no blanks, no trailing
  # comments, no eval prefix, no leading whitespace; then sorted
  grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$' \
    | sed -e 's/[[:space:]][[:space:]]*#.*//' -e 's/[[:space:]]*$//' \
          -e 's/^[[:space:]]*//' -e 's/^eval //' | sort
}

norm "$TIGER/tigris.conf" > "$W/rc.txt"
norm "$TIGER/tigris-quick.conf" > "$W/quick.txt"
# comm, not diff: busybox's diff and an image without diffutils differ.
# Lines only in tigris.conf come out as "< line", only in tigris-quick.conf "> line"
comm -3 "$W/rc.txt" "$W/quick.txt" | sed -e 's/^	/> /' -e 's/^\([^>]\)/< \1/' > "$W/diff.txt"
if [ ! -s "$W/diff.txt" ]; then
  bad "tigris-quick.conf is identical to tigris.conf; it must turn the scan off"
elif [ "`grep -c '^[<>]' "$W/diff.txt"`" -eq 2 ] && \
     grep -q '^< Tigris_Check_FILESYSTEM=Y$' "$W/diff.txt" && \
     grep -q '^> Tigris_Check_FILESYSTEM=N$' "$W/diff.txt"; then
  ok "tigris-quick.conf differs from tigris.conf only in Tigris_Check_FILESYSTEM"
else
  bad "settings drifted between tigris.conf and tigris-quick.conf:"
  sed -e 's/^< /     tigris.conf:       /' -e 's/^> /     tigris-quick.conf: /' "$W/diff.txt"
  fail=1
fi

# The profiles are overlays: each sets only settings the tigris.conf has (a
# mistyped name would otherwise do nothing), and quick is what turns
# tigris.conf into tigris-quick.conf
known=`sed -n 's/^\([A-Za-z_][A-Za-z_0-9]*\)=.*/\1/p' "$W/rc.txt" | sort -u`
for p in "$TIGER"/profiles/*
do
  name=${p##*/}
  unknown=`norm "$p" | sed -n 's/^\([A-Za-z_][A-Za-z_0-9]*\)=.*/\1/p' | sort -u | while read v; do echo "$known" | grep -qx "$v" || echo "$v"; done`
  [ -z "$unknown" ] && ok "profile $name sets only settings tigris.conf has" || bad "profile $name sets settings tigris.conf does not have: `echo $unknown`"
  case "$name" in *[!a-z0-9_-]*) bad "profile name $name is not letters, digits, - and _" ;; esac
done
# tigris.conf with the quick profile on top, as config reads them: later wins
norm "$TIGER/profiles/quick" > "$W/pquick.txt"
awk -F= 'NR == FNR { p[$1] = $0; next } { print ($1 in p) ? p[$1] : $0 }' "$W/pquick.txt" "$W/rc.txt" | sort > "$W/overlay.txt"
if [ -z "`comm -3 "$W/overlay.txt" "$W/quick.txt"`" ]; then
  ok "tigris.conf with profiles/quick on top is tigris-quick.conf"
else
  bad "tigris.conf + profiles/quick differs from tigris-quick.conf:"; comm -3 "$W/overlay.txt" "$W/quick.txt" | sed 's/^/     /'
fi

# config itself: --profile applies it, a missing one stops the run
X=`mktemp -d`
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$X" && tar -xf - )
mkdir -p "$X/run" "$X/log"
printf 'basedir=$TIGERHOMEDIR\n. $basedir/config\necho "FILESYSTEM=$Tigris_Check_FILESYSTEM USB=$Tigris_Storage_NoUSB PROFILE=$PROFILE"\n' > "$X/drive.sh"
( cd "$X" && TIGERHOMEDIR=$X sh ./drive.sh --profile quick 2>&1 ) | grep -q '^FILESYSTEM=N USB=N PROFILE=quick$' &&
  ok "--profile quick turns the scan off" || bad "--profile quick"
( cd "$X" && TIGERHOMEDIR=$X sh ./drive.sh -p server 2>&1 ) | grep -q '^FILESYSTEM=Y USB=Y PROFILE=server$' &&
  ok "-p server forbids USB storage and keeps the scan" || bad "-p server"
mkdir -p "$X/profiles"; printf 'Tigris_Storage_NoUSB=Y\n' > "$X/profiles/site"; chmod 644 "$X/profiles/site"
( cd "$X" && TIGERHOMEDIR=$X sh ./drive.sh -c "$X/tigris.conf" --profile site 2>&1 ) | grep -q 'USB=Y PROFILE=site$' &&
  ok "a site's own profile, beside the tigris.conf" || bad "site profile"
out=`cd "$X" && TIGERHOMEDIR=$X sh ./drive.sh --profile nosuch 2>&1`; st=$?
[ $st -ne 0 ] && echo "$out" | grep -q 'con013e.*There is no profile .nosuch.' && ! echo "$out" | grep -q '^FILESYSTEM=' &&
  ok "an unknown profile: con013e, and the run stops" || bad "unknown profile: $out"
rm -rf "$X"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
