#!/bin/sh
#
# tests/deb_checks.sh - the Debian package checks against planted problems
#
# Run as root in a throwaway Debian or Ubuntu container. It modifies one
# packaged binary, deletes another, adds a stray file to /usr/sbin, an
# override (dpkg-statoverride, without --update) that a binary does not
# match, a removed-but-not-purged package in the dpkg status, a
# diversion whose diverted-to copy was changed and three strays named so
# that a shell's read or a dpkg -S pattern would take them for
# /usr/bin/diff, then runs deb_checkmd5sums, deb_nopackfiles and
# deb_statoverride from a root-owned copy of this tree and checks that
# exactly those are reported. Where /usr is not merged it also copies
# /bin/su to /usr/bin/su, a stray there however packaged its twin is.
# deb_nopackfiles runs again with Tigris_DPKG_Optimize=N, its dpkg -S
# lookup, which must find the same unowned files. Then it copies the
# container's root, changes and all, into a directory and runs the three
# on that as an offline root (TIGRIS_ROOT, as tigris --root sets it): the
# report must be the same.
#
# Exit 0 when every assertion holds, 1 otherwise, 2 when it cannot run.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}

[ "`id -u`" = 0 ] || { echo "SKIP: must run as root, in a throwaway container"; exit 2; }
[ -d /var/lib/dpkg/info ] || { echo "SKIP: not a dpkg system"; exit 2; }
[ -f /.dockerenv ] || [ -n "$CI" ] || [ -n "$TIGER_TEST_I_MEAN_IT" ] || {
  echo "SKIP: this test damages the system it runs on; set TIGER_TEST_I_MEAN_IT=1 in a container"; exit 2; }

W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
chown -R 0:0 "$W"
mkdir -p "$W/run" "$W/log"

# Plant the problems
echo tampered >> /usr/bin/xargs
rm -f /usr/bin/sdiff
echo x > /usr/sbin/zz-tiger-stray
dpkg-statoverride --add root root 0700 /usr/bin/cmp
# a local diversion whose diverted-to copy differs from the package's file
dpkg-divert --local --no-rename --divert /usr/bin/tac.distrib --add /usr/bin/tac >/dev/null
cp /usr/bin/tac /usr/bin/tac.distrib && echo tampered >> /usr/bin/tac.distrib
printf '\nPackage: zz-tiger-unpurged\nStatus: deinstall ok config-files\nArchitecture: amd64\nVersion: 1.0\n' >> /var/lib/dpkg/status
# Strays a shell's read or a dpkg -S pattern would take for the packaged
# /usr/bin/diff: a trailing blank, a backslash, a *
for name in '/usr/bin/diff ' '/usr/bin/d\iff' '/usr/bin/dif*'
do
  echo x > "$name"
done
# Where /usr is not merged, /bin/su and /usr/bin/su are two files: a copy
# at the second is a stray, though dpkg owns the first
unmerged=
if [ ! -L /bin ] && [ -f /bin/su ] && [ ! -e /usr/bin/su ]; then
  cat /bin/su > /usr/bin/su && chmod 755 /usr/bin/su && unmerged=1
fi

cd "$W"
run()
{
  for check in ${*:-deb_checkmd5sums deb_nopackfiles deb_statoverride}
  do
    TIGERHOMEDIR=$W sh systems/Linux/2/$check
  done 2>&1 |
  # Join the lines Tiger wraps, so a path is on the same line as its code
  awk '/^--/ { if (l != "") print l; l = $0; next } /^[ \t]/ { sub(/^[ \t]+/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  grep -v '^--CONFIG--' | sort
}
run > "$W/report"

fail=0
expect()
{
  if grep -q "$1" "$W/report"; then
    echo "ok   $2"
  else
    echo "FAIL $2"
    fail=1
  fi
}
expect "lin005f.*/usr/bin/xargs"       "modified binary reported (lin005f)"
expect "lin006f.*/usr/bin/sdiff"       "deleted binary reported (lin006f)"
expect "lin001w.*/usr/sbin/zz-tiger-stray" "stray file reported (lin001w)"
expect "lin039w.*/usr/bin/cmp.*sets root:root 700; the file is root:root 755" "file not matching its override reported (lin039w)"
expect "lin042w.*zz-tiger-unpurged" "removed but not purged package reported (lin042w)"
expect "lin005f.*/usr/bin/tac.distrib" "modified copy of a diverted binary reported (lin005f)"
[ -n "$unmerged" ] &&
  expect "lin001w.*/usr/bin/su'" "/usr/bin/su beside the packaged /bin/su reported where /usr is not merged (lin001w)"
named()   # named NAME WHAT: a lin001w for exactly that name
{
  if grep lin001w "$W/report" | grep -q -F "\`$1'"; then
    echo "ok   $2"
  else
    echo "FAIL $2"; fail=1
  fi
}
named '/usr/bin/diff ' "stray whose name ends in a blank reported by its name (lin001w)"
named '/usr/bin/d\iff' "stray with a backslash in its name reported by its name (lin001w)"
named '/usr/bin/dif*' "stray with a * in its name reported by its name (lin001w)"
if [ "`grep -c lin039w "$W/report"`" = 1 ]; then
  echo "ok   no other override mismatches"
else
  echo "FAIL other override mismatches:"; grep lin039w "$W/report"; fail=1
fi

# Docker drops /usr/sbin/policy-rc.d into images; nothing else may be unowned
cat > "$W/planted" <<'EOF'
`/usr/sbin/zz-tiger-stray'
`/usr/sbin/policy-rc.d'
`/usr/bin/diff '
`/usr/bin/d\iff'
`/usr/bin/dif*'
EOF
[ -n "$unmerged" ] && echo "\`/usr/bin/su'" >> "$W/planted"
unowned=`grep -c 'lin001w' "$W/report"`
others=`grep 'lin001w' "$W/report" | grep -v -c -F -f "$W/planted"`
if [ "$others" -eq 0 ]; then
  echo "ok   no other unowned files ($unowned lin001w in all)"
else
  echo "FAIL $others unexpected unowned files:"
  grep 'lin001w' "$W/report" | grep -v -F -f "$W/planted" | head -5
  fail=1
fi

# The dpkg -S lookup must find the same unowned files as the default one
optimize()
{
  sed "s/^Tigris_DPKG_Optimize=.*/Tigris_DPKG_Optimize=$1/" "$W/tigris.conf" > "$W/conf.tmp" &&
  cat "$W/conf.tmp" > "$W/tigris.conf" && rm -f "$W/conf.tmp"
}
optimize N
run deb_nopackfiles | grep lin001w > "$W/unowned.dpkg"
optimize Y
if grep lin001w "$W/report" | cmp -s - "$W/unowned.dpkg"; then
  echo "ok   Tigris_DPKG_Optimize=N: the same unowned files"
else
  echo "FAIL Tigris_DPKG_Optimize=N differs (default only, then dpkg -S only):"
  grep lin001w "$W/report" | comm -3 - "$W/unowned.dpkg"; fail=1
fi

# The same system as an offline root: this container's files copied into a
# directory, with empty /proc, /sys and /dev as a mounted image has
IMG=/tigris-img
rm -rf "$IMG"; mkdir -p "$IMG"
tar -C / --exclude=./proc --exclude=./sys --exclude=./dev --exclude=.$IMG --exclude=.$W --exclude=./tiger -cf - . 2>/dev/null | tar -C "$IMG" -xpf -
mkdir -p "$IMG/proc" "$IMG/sys" "$IMG/dev"
# A packaged binary replaced by an absolute link to the same file elsewhere
# in the root: followed inside the root its sums match; followed on this
# host, where there is no /opt/zz-tiger-diff, it would be missing
mkdir -p "$IMG/opt"
mv "$IMG/usr/bin/diff" "$IMG/opt/zz-tiger-diff"
ln -s /opt/zz-tiger-diff "$IMG/usr/bin/diff"
TIGRIS_ROOT=$IMG run > "$W/offline"
rm -rf "$IMG"
if [ "`cat "$W/report"`" = "`cat "$W/offline"`" ]; then
  echo "ok   offline root: the same report, by the root's paths"
else
  echo "FAIL offline report differs from the live one (live only, then offline only):"; comm -3 "$W/report" "$W/offline"; fail=1
fi

[ $fail -eq 0 ] && echo "PASS" || { echo "--- report"; cat "$W/report"; }
exit $fail
