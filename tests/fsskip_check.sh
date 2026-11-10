#!/bin/sh
#
# tests/fsskip_check.sh - whole file systems left out of the scan, and said
#
# Tigris_FSScan_SkipTypes and Tigris_FSScan_SkipMounts are the fast path
# for a large data disk. Runs the file system scan (scripts/find_files, as
# tigris runs it) over a mount table of its own (Tigris_Mounts_Cmd), every
# "mount point" a directory of the fixture that holds a directory named
# "...", which the scan reports (fsys005a) wherever it walks. Requires:
#
#  - a file system of a skipped type is not walked, and con021c names it,
#    its type and the setting; a type is matched whole (ext does not skip
#    ext4), in a list separated by spaces or pipes;
#  - the file system at a skipped mount point is not walked, nor one
#    mounted below it, and con021c names each; a mount point that only
#    begins with the same letters is walked;
#  - a mount point is data, whoever named it: one with a space in its name
#    next to a skipped one, one with a quote, one with $HOME and one named
#    "*" are walked as named, the setting is not a pattern either (gl*b is
#    skipped, glxxb is not), and nothing skipped is walked through them;
#  - with neither setting, everything is walked and nothing is said.
#
# Then gen_mounts is replaced by one that also hands over a mount point
# beginning with a dash: find_files drops it and scans the rest.
#
# The offline side (--root) is in offline_scan_check.sh. Needs GNU find
# (busybox's slower path does not report these names at all) and no root;
# touches nothing outside a temporary directory.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
find / -maxdepth 0 -printf '' 2>/dev/null || { echo "ok   (no GNU find here: nothing to test)"; echo PASS; exit 0; }
[ "`uname -s`" = Linux ] || { echo "ok   (the mount table read here is Linux's: nothing to test)"; echo PASS; exit 0; }

W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log" "$W/fx"
[ "`id -u`" = 0 ] && chown -R 0:0 "$W"

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

F=$W/fx
for d in sys data data/sub "data x" datab tank vol "it's" 'cost$HOME' '*' 'gl*b' glxxb
do
  mkdir -p "$F/$d/..."
done
{
  echo '#!/bin/sh'
  echo "cat <<'TABLE'"
  for d in sys data data/sub "data x" datab "it's" 'cost$HOME' '*' 'gl*b' glxxb
  do
    printf '/dev/sdy1 on %s type ext4 (rw,relatime)\n' "$F/$d"
  done
  printf '/dev/sdy2 on %s type xfs (rw,relatime)\n' "$F/tank"
  printf '/dev/sdy3 on %s type jfs (rw,relatime)\n' "$F/vol"
  echo TABLE
} > "$F/mount"
chmod +x "$F/mount"
cp "$W/tigris.conf" "$W/tigris.conf.orig"

# scan OUTFILE SETTINGS...: the scan with these lines after the tigris.conf's
scan()
{
  __out=$1; shift
  cp "$W/tigris.conf.orig" "$W/tigris.conf"
  {
    echo "Tigris_Mounts_Cmd='$F/mount'"
    echo 'Tigris_FSScan_ofNote=Y'
    echo "Tigris_FSScan_DetailDirs='*'"
    echo "Tigris_FSScan_PruneDirs=''"
    for __line; do printf '%s\n' "$__line"; done
  } >> "$W/tigris.conf"
  # (_TIGER_RUN as tiger sets it: else each sub/ check's cleanup deletes
  # the others' messages)
  ( cd "$W" && _TIGER_RUN=Y TIGERHOMEDIR=$W sh scripts/find_files ) > "$__out" 2>&1
}
walked() { grep -qF -- "$F/$1/..." "$2"; }
# said MOUNTPOINT TYPE REASON FILE: one con021c line that says all three
# (the text is wrapped at 79 columns: join a finding's lines first)
said()
{
  awk '/^--/ { if (l != "") print l; l = $0; next }
       /^ / { sub(/^ +/, " "); l = l $0; next }
       { if (l != "") print l; l = "" }
       END { if (l != "") print l }' "$4" |
    grep -F -- '--CONFIG-- [con021c]' | grep -F -- "File system $F/$1 ($2) is left out" | grep -qF -- "$3"
}

# 1. neither setting: every mount point is walked, nothing is said
scan "$W/all.out"
missing=
for d in sys data "data x" datab tank vol "it's" 'cost$HOME' '*' 'gl*b' glxxb
do
  walked "$d" "$W/all.out" || missing="$missing [$d]"
done
[ -z "$missing" ] && ok "neither setting: every file system is walked" ||
  { bad "neither setting, and not walked:$missing"; sed 's/^/     /' "$W/all.out"; }
grep -q 'con02[12]c' "$W/all.out" && bad "neither setting, and a file system is said to be left out" ||
  ok "neither setting: nothing is said"

# 2. by type
scan "$W/type.out" "Tigris_FSScan_SkipTypes='ext xfs|jfs'"
walked tank "$W/type.out" && bad "a file system of a skipped type (xfs) was walked" || ok "a skipped type is not walked"
walked vol "$W/type.out" && bad "the type after a pipe (jfs) was walked" || ok "types separated by a space or a pipe"
said tank xfs 'Tigris_FSScan_SkipTypes names its type' "$W/type.out" && said vol jfs 'Tigris_FSScan_SkipTypes' "$W/type.out" &&
  ok "con021c names the file system, its type and the setting" || { bad "no con021c for the skipped types"; grep -A2 con021c "$W/type.out"; }
walked sys "$W/type.out" && walked data "$W/type.out" &&
  ok "a type is matched whole: ext does not skip ext4" || bad "ext4 was skipped for ext"
[ "`grep -c 'con021c' "$W/type.out"`" = 2 ] && ok "two file systems left out, two lines" ||
  bad "`grep -c con021c "$W/type.out"` con021c lines, not 2"

# 3. by mount point, among names that are not what they seem
scan "$W/mnt.out" "Tigris_FSScan_SkipMounts='$F/data/|$F/gl*b|relative|'"
walked data "$W/mnt.out" && bad "a skipped mount point was walked" || ok "a skipped mount point is not walked"
walked data/sub "$W/mnt.out" && bad "a file system mounted below a skipped mount point was walked" ||
  ok "nor is a file system mounted below it"
said data ext4 'Tigris_FSScan_SkipMounts names it' "$W/mnt.out" && ok "con021c names the mount point and the setting" ||
  { bad "no con021c for the skipped mount point"; grep -A2 con021c "$W/mnt.out"; }
said data/sub ext4 "it is mounted below $F/data, which Tigris_FSScan_SkipMounts names" "$W/mnt.out" &&
  ok "con021c for the one below, saying why" || { bad "no con021c for the file system below"; grep -A2 con021c "$W/mnt.out"; }
walked "data x" "$W/mnt.out" && ok "a mount point with a space, named like a skipped one, is walked as named" ||
  bad "the mount point with a space was not walked"
walked datab "$W/mnt.out" && ok "a mount point that only begins with a skipped one's name is walked" ||
  bad "datab was skipped for data"
walked "it's" "$W/mnt.out" && ok "a mount point with a quote in its name is walked" || bad "the quoted mount point was not walked"
walked 'cost$HOME' "$W/mnt.out" && ok "a mount point with \$HOME in its name is walked as named" ||
  bad "the \$HOME mount point was not walked"
walked '*' "$W/mnt.out" && ok "a mount point named * is walked as named" || bad "the mount point named * was not walked"
walked 'gl*b' "$W/mnt.out" && bad "a skipped mount point with a * in its name was walked" ||
  ok "a setting with a * in it names that mount point"
walked glxxb "$W/mnt.out" && ok "and no other: the setting is not a pattern" || bad "gl*b skipped glxxb"
walked sys "$W/mnt.out" && walked tank "$W/mnt.out" && ok "the rest is walked" || bad "the rest was not walked"
[ "`grep -c 'con021c' "$W/mnt.out"`" = 3 ] && ok "three file systems left out, three lines" ||
  bad "`grep -c con021c "$W/mnt.out"` con021c lines, not 3"
grep -q 'unexpected\|[Ss]yntax error\|not found' "$W/mnt.out" && { bad "the shell read a name"; grep -n 'unexpected\|yntax error\|not found' "$W/mnt.out"; } ||
  ok "no name was read by the shell"

# 4. find_files on its own, whatever a gen_mounts says: this copy's are
# replaced by one that hands over a mount point beginning with a dash,
# which find would take for an expression (one it does not know, so it
# would stop and scan nothing)
{
  echo '#!/bin/sh'
  echo "cat <<'TABLE'"
  printf '%s ext4 /dev/sdy1\n' "$F/sys" "-zz-not-a-path" "$F/datab"
  echo TABLE
} > "$F/gen_mounts"
for g in "$W"/systems/Linux/*/gen_mounts; do cat "$F/gen_mounts" > "$g"; done
scan "$W/dash.out"
walked sys "$W/dash.out" && walked datab "$W/dash.out" &&
  ok "a mount point that is no absolute path is dropped, and the rest is scanned" ||
  { bad "a mount point beginning with a dash stopped the scan"; sed 's/^/     /' "$W/dash.out"; }

[ $fail -eq 0 ] && echo "PASS" || echo "fsskip_check: FAILED"
exit $fail
