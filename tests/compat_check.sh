#!/bin/sh
#
# tests/compat_check.sh - the 4.0 rename keeps old configurations working
#
# tigris.conf, Tigris_* settings, /etc/tigris and tigris-explain are the
# names; a tigerrc, Tiger_* settings, /etc/tiger and tigexp still work.
# A dead apt source (120 days, judged against Tigris_Repos_Now) proves
# the settings legs: Tigris_Repos_MaxAge=200 silences it, 90 reports it.
# An old file beats a new file in the same directory, so no new default
# appearing beside an old file may silently switch the admin's settings;
# an explicit new setting beats an old one. /etc/tiger itself is not
# exercised (writing /etc is not a test's business); the search list
# holding it is covered through $HOME instead.
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

R=$W/root; mkdir -p "$R/etc" "$R/var/lib/apt/lists"
cat > "$R/var/lib/apt/lists/old_packager_io_repo_dists_stable_Release" <<'EOF'
Origin: Packager
Suite: stable
Date: Tue, 16 Jun 2026 10:40:00 UTC
Valid-Until: Fri, 13 Nov 2026 10:40:00 UTC
EOF
touch -t 202001010000 "$R/var/lib/apt/lists/old_packager_io_repo_dists_stable_Release"
run() {  # run OUTFILE [EXTRA-ENV]: check_repos over the dead source
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$R" ${2:+$2} sh ./systems/Linux/2/check_repos ) > "$1" 2>&1 || true
}

# an old setting in the tigris.conf is honored
printf '# minimal\nTigris_Repos_Now=1791974400\nTiger_Repos_MaxAge=200\n' > "$W/tigris.conf"
run "$W/out"
! grep -q 'upd007w' "$W/out" &&
  ok "Tiger_Repos_MaxAge in tigris.conf: honored" || { bad "old setting in rc"; grep '^--' "$W/out" | head -3; }

# an old setting from the environment is honored
printf '# minimal\nTigris_Repos_Now=1791974400\n' > "$W/tigris.conf"
run "$W/out" "Tiger_Repos_MaxAge=200"
! grep -q 'upd007w' "$W/out" &&
  ok "Tiger_Repos_MaxAge from the environment: honored" || { bad "old setting from env"; grep '^--' "$W/out" | head -3; }

# an explicit new setting beats an old one
printf '# minimal\nTigris_Repos_Now=1791974400\nTiger_Repos_MaxAge=200\nTigris_Repos_MaxAge=90\n' > "$W/tigris.conf"
run "$W/out"
grep -q -- '--WARN-- \[upd007w\]' "$W/out" &&
  ok "Tigris_Repos_MaxAge=90 beside Tiger_=200: the new spelling wins" || { bad "new does not win"; grep '^--' "$W/out" | head -3; }

# an old profile is honored too
printf '# minimal\nTigris_Repos_Now=1791974400\n' > "$W/tigris.conf"
printf 'Tiger_Repos_MaxAge=200\n' > "$W/profiles/oldleg"; chmod 644 "$W/profiles/oldleg"
printf 'basedir=$TIGERHOMEDIR\n. $basedir/config\necho "MAX=$Tigris_Repos_MaxAge"\n' > "$W/drive.sh"
( cd "$W" && TIGERHOMEDIR=$W sh ./drive.sh --profile oldleg ) > "$W/out" 2>&1
grep -q '^MAX=200$' "$W/out" &&
  ok "a profile saying Tiger_: honored" || { bad "old setting in profile"; cat "$W/out"; }

# a tigerrc alone is found and read
rm "$W/tigris.conf"
printf '# old name\nTigris_Repos_Now=1791974400\nTiger_Repos_MaxAge=200\n' > "$W/tigerrc"; chmod 644 "$W/tigerrc"
run "$W/out"
! grep -q 'upd007w' "$W/out" &&
  ok "a lone tigerrc: found, and its old setting honored" || { bad "lone tigerrc"; grep '^--' "$W/out" | head -3; }

# an old file beats a new file beside it
printf '# minimal\nTigris_Repos_Now=1791974400\n' > "$W/tigris.conf"; chmod 644 "$W/tigris.conf"
run "$W/out"
! grep -q 'upd007w' "$W/out" &&
  ok "tigerrc beside tigris.conf: the old file wins" || { bad "old file does not win"; grep '^--' "$W/out" | head -3; }

# a rejected preset falls through to an old name later in the search
chmod 664 "$W/tigerrc"
rm "$W/tigris.conf"
mkdir -p "$W/home"
printf '# old name\nTigris_Repos_Now=1791974400\nTiger_Repos_MaxAge=200\n' > "$W/home/.tigerrc"; chmod 644 "$W/home/.tigerrc"
( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$R" HOME="$W/home" sh ./systems/Linux/2/check_repos ) > "$W/out" 2>&1 || true
! grep -q 'upd007w' "$W/out" &&
  ok "rejected ./tigerrc falls through to ~/.tigerrc" || { bad "search fallback"; grep '^--' "$W/out" | head -5; }
[ "`grep -c 'con003c' "$W/out"`" = 1 ] &&
  ok "the rejection is said once" || bad "con003c `grep -c con003c "$W/out"` times"
chmod 644 "$W/tigerrc"; rm "$W/home/.tigerrc"

# an old camelCase setting from the environment is honored
printf 'basedir=$TIGERHOMEDIR\n. $basedir/config\necho "BINDIR=$BINDIR"\n' > "$W/drive.sh"
printf '# minimal\nTigris_Repos_Now=1791974400\n' > "$W/tigris.conf"
( cd "$W" && TIGERHOMEDIR=$W TigerBinDir=/x sh ./drive.sh ) > "$W/out" 2>&1
grep -q '^BINDIR=/x$' "$W/out" &&
  ok "TigerBinDir from the environment: honored" || { bad "old camelCase setting"; cat "$W/out"; }

# the shim leaves none of its own variables behind
printf 'basedir=$TIGERHOMEDIR\n. $basedir/config\necho "OLD=${__old-unset} NEW=${__new-unset} SH=${__shimmed-unset}"\n' > "$W/drive.sh"
( cd "$W" && TIGERHOMEDIR=$W sh ./drive.sh ) > "$W/out" 2>&1
grep -q '^OLD=unset NEW=unset SH=unset$' "$W/out" &&
  ok "the shim unsets its loop variables" || { bad "shim leaks"; grep '^OLD=' "$W/out"; }

# tigexp still runs the explanation
[ -L "$TIGER/tigexp" ] && ok "tigexp is a symlink" || bad "tigexp is not a symlink"
( cd "$W" && sh ./tigexp lin002i ) > "$W/out" 2>&1
grep -q 'Severity:' "$W/out" &&
  ok "tigexp explains an id" || { bad "tigexp shim"; cat "$W/out"; }

# nothing else still says the old names: code, shipped configuration,
# tests and metadata use the new ones, except the shims themselves, the
# old-report fixtures, and this suite
D='systems scripts tiger tigercron tigris-diff tigris-accept tigris-explain config initdefs util profiles tigris.conf tigris-quick.conf tests meta Makefile.in configure configure.in install.sh cronrc packaging debian .github tigris.spec Dockerfile check.d site-sample site-saturn'
( cd "$TIGER" && grep -rln 'Tiger_[A-Za-z0-9]\|Tiger[A-Z]' $D 2>/dev/null ) | grep -v '^debian/changelog$' > "$W/vars.txt"
left=`grep -v -x -e config -e tests/compat_check.sh "$W/vars.txt"`
[ -z "$left" ] && ok "no Tiger_* stragglers outside the shim" || { bad "Tiger_ stragglers: $left"; }
( cd "$TIGER" && grep -rln 'tigerrc' $D 2>/dev/null ) | grep -v '^debian/changelog$' > "$W/rc.txt"
left=`grep -v -x -e config -e tigris-accept -e profiles/quick -e tests/compat_check.sh -e tests/diff_check.sh -e tests/nonroot_check.sh -e tests/schema_check.sh "$W/rc.txt"`
[ -z "$left" ] && ok "no tigerrc stragglers outside the shims and old-report fixtures" || { bad "tigerrc stragglers: $left"; }
( cd "$TIGER" && grep -rln '/etc/tiger' $D 2>/dev/null ) | grep -v '^debian/changelog$' > "$W/etc.txt"
left=`grep -v -x -e config -e tigris-accept -e tests/compat_check.sh "$W/etc.txt"`
[ -z "$left" ] && ok "no /etc/tiger stragglers outside the fallbacks" || { bad "/etc/tiger stragglers: $left"; }
( cd "$TIGER" && grep -rn 'tigexp' $D 2>/dev/null ) | grep -v 'tigris-explain' | grep -v '^debian/changelog:' | grep -v '^Binary' | sed 's/:.*//' | sort -u > "$W/exp.txt"
left=`grep -v -x -e tests/compat_check.sh "$W/exp.txt"`
[ -z "$left" ] && ok "no bare tigexp outside this suite" || { bad "tigexp stragglers: $left"; }

[ $fail -eq 0 ] && echo PASS || echo FAIL
exit $fail
