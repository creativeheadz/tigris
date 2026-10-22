#!/bin/sh
#
# tests/repos_check.sh - check_repos on offline roots
#
# Thirteen roots, all judged against Tigris_Repos_Now=1791974400
# (14 Oct 2026), so the ages never rot: apt judged by newest suite
# (an old release pocket beside fresh updates is fine, whichever
# files are fresh); an apt source dead 120 days; an apt source
# freshly published but Valid-Until passed; an apt source with an
# old Date still re-fetched (served, not dead); apt lists never
# refreshed; dnf with a dead repo beside a fresh one; zypper the
# same; pacman with a dead repo beside a fresh one (URLs through
# Server and Include); a lone dead pacman database (refresh, not
# stale); apk both ways; and an empty root, where no manager exists
# and nothing is said. Runs as a user and as root; the fixtures
# read the same for both.
#
TIGER=${TIGER:-`cd "\`dirname \"$0\"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
cp "$W/tigris.conf" "$W/tigris.conf.base"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run() {  # run ROOT OUTFILE [EXTRA]: check_repos with ROOT as the audited system
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { echo "Tigris_Repos_Now=1791974400"; } >> "$W/tigris.conf"
  [ -n "$3" ] && { echo "$3" >> "$W/tigris.conf"; }
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/Linux/2/check_repos ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }
release() {  # release FILE ORIGIN SUITE DATE VALIDUNTIL
  { echo "Origin: $2"; echo "Suite: $3"; echo "Date: $4"; echo "Valid-Until: $5"; } > "$1"
}

A1=$W/apt1; mkdir -p "$A1/etc" "$A1/var/lib/apt/lists"
release "$A1/var/lib/apt/lists/deb_debian_org_debian_dists_trixie_InRelease" Debian trixie 'Sat, 01 Jun 2024 00:00:00 UTC' 'Fri, 13 Nov 2026 10:40:00 UTC'
release "$A1/var/lib/apt/lists/deb_debian_org_debian_dists_trixie-updates_InRelease" Debian trixie-updates 'Sun, 04 Oct 2026 10:40:00 UTC' 'Fri, 13 Nov 2026 10:40:00 UTC'
touch -t 202001010000 "$A1/var/lib/apt/lists/deb_debian_org_debian_dists_trixie_InRelease" "$A1/var/lib/apt/lists/deb_debian_org_debian_dists_trixie-updates_InRelease"
printf 'package list\n' > "$A1/var/lib/apt/lists/deb_debian_org_debian_dists_trixie-updates_main_binary-amd64_Packages"
run "$A1" "$W/out"
! grep -q 'upd007w' "$W/out" && ! grep -q 'upd009w' "$W/out" && ! grep -q 'upd008w' "$W/out" &&
  ok "old pocket beside fresh updates: newest suite wins" || { bad "apt1"; cat "$W/out"; }

A2=$W/apt2; mkdir -p "$A2/etc" "$A2/var/lib/apt/lists"
release "$A2/var/lib/apt/lists/old_packager_io_repo_dists_stable_Release" Packager stable 'Tue, 16 Jun 2026 10:40:00 UTC' 'Fri, 13 Nov 2026 10:40:00 UTC'
touch -t 202001010000 "$A2/var/lib/apt/lists/old_packager_io_repo_dists_stable_Release"
printf 'package list\n' > "$A2/var/lib/apt/lists/other_example_com_Packages"
run "$A2" "$W/out"
has '--WARN-- [upd007w]' "$W/out" &&
has 'old_packager_io_repo_dists_stable_Release' "$W/out" &&
has 'from Packager, suite stable' "$W/out" &&
has 'published 120 days ago' "$W/out" &&
! grep -q 'upd009w' "$W/out" && ! grep -q 'upd008w' "$W/out" &&
  ok "dead source: upd007w naming file, origin, age" || { bad "apt2"; cat "$W/out"; }
run "$A2" "$W/out" "Tigris_Repos_MaxAge=200"
! grep -q 'upd007w' "$W/out" &&
  ok "MaxAge=200: the same source is fine" || { bad "maxage"; cat "$W/out"; }

A3=$W/apt3; mkdir -p "$A3/etc" "$A3/var/lib/apt/lists"
release "$A3/var/lib/apt/lists/repo_example_com_debian_dists_stable_InRelease" Example stable 'Sun, 04 Oct 2026 10:40:00 UTC' 'Fri, 09 Oct 2026 10:40:00 UTC'
run "$A3" "$W/out"
has '--WARN-- [upd009w]' "$W/out" &&
has 'expired on 09 Oct 2026' "$W/out" &&
! grep -q 'upd007w' "$W/out" &&
  ok "fresh but Valid-Until passed: upd009w, not upd007w" || { bad "apt3"; cat "$W/out"; }

A5=$W/apt5; mkdir -p "$A5/etc" "$A5/var/lib/apt/lists"
release "$A5/var/lib/apt/lists/neglect_example_com_dists_stable_InRelease" Neglect stable 'Tue, 16 Jun 2026 10:40:00 UTC' 'Fri, 13 Nov 2026 10:40:00 UTC'
run "$A5" "$W/out"
! grep -q 'upd007w' "$W/out" &&
  ok "old Date, freshly fetched: still served, nothing" || { bad "apt5"; cat "$W/out"; }

A6=$W/apt6; mkdir -p "$A6/etc" "$A6/var/lib/apt/lists"
release "$A6/var/lib/apt/lists/deb_debian_org_debian_dists_trixie_InRelease" Debian trixie 'Sat, 01 Jun 2024 00:00:00 UTC' 'Fri, 13 Nov 2026 10:40:00 UTC'
release "$A6/var/lib/apt/lists/deb_debian_org_debian_dists_trixie-updates_InRelease" Debian trixie-updates 'Sun, 04 Oct 2026 10:40:00 UTC' 'Fri, 13 Nov 2026 10:40:00 UTC'
touch -t 202001010000 "$A6/var/lib/apt/lists/deb_debian_org_debian_dists_trixie_InRelease"
run "$A6" "$W/out"
! grep -q 'upd007w' "$W/out" && ! grep -q 'upd008w' "$W/out" &&
  ok "old pocket file beside fresh updates file: grouped, nothing" || { bad "apt6"; cat "$W/out"; }

A4=$W/apt4; mkdir -p "$A4/etc" "$A4/var/lib/apt/lists/partial"
printf 'package list\n' > "$A4/var/lib/apt/lists/repo_example_com_Packages"
touch -t 202001010000 "$A4/var/lib/apt/lists/repo_example_com_Packages"
run "$A4" "$W/out"
has '--WARN-- [upd008w] The apt package lists were last refreshed over 90 days ago' "$W/out" &&
! grep -q 'upd007w' "$W/out" &&
  ok "lists never refreshed: upd008w" || { bad "apt4"; cat "$W/out"; }

D=$W/dnf; mkdir -p "$D/etc" "$D/etc/yum.repos.d" "$D/var/cache/dnf/fedora-abcdef0123456789/repodata" "$D/var/cache/dnf/updates-0123456789abcdef/repodata"
printf '[fedora]\nbaseurl=https://dl.example.com/fedora\n' > "$D/etc/yum.repos.d/fedora.repo"
printf '<repomd><revision>1</revision><timestamp>1781606400</timestamp></repomd>\n' > "$D/var/cache/dnf/fedora-abcdef0123456789/repodata/repomd.xml"
printf '<repomd><revision>2</revision><timestamp>1791110400</timestamp></repomd>\n' > "$D/var/cache/dnf/updates-0123456789abcdef/repodata/repomd.xml"
run "$D" "$W/out"
has "Repository 'fedora' (https://dl.example.com/fedora) published 120 days ago" "$W/out" &&
! grep -q 'updates' "$W/out" && ! grep -q 'upd008w' "$W/out" &&
  ok "dnf dead repo beside fresh: upd007w with URL" || { bad "dnf"; cat "$W/out"; }

Z=$W/zypper; mkdir -p "$Z/etc" "$Z/var/cache/zypp/raw/packman" "$Z/var/cache/zypp/raw/oss"
printf '<repomd><revision>1</revision><timestamp>1781606400</timestamp></repomd>\n' > "$Z/var/cache/zypp/raw/packman/repomd.xml"
printf '<repomd><revision>2</revision><timestamp>1791110400</timestamp></repomd>\n' > "$Z/var/cache/zypp/raw/oss/repomd.xml"
run "$Z" "$W/out"
has "Repository 'packman' (see /etc/zypp/repos.d) published 120 days ago" "$W/out" &&
  ok "zypper dead repo, no .repo file: URL fallback" || { bad "zypper"; cat "$W/out"; }

P=$W/pacman; mkdir -p "$P/etc" "$P/etc/pacman.d" "$P/var/lib/pacman/sync"
printf '[options]\n[core]\nInclude = /etc/pacman.d/mirrorlist\n[oldrepo]\nInclude = /etc/pacman.d/mirrorlist-old\n' > "$P/etc/pacman.conf"
printf 'Server = https://mirror.example.com/$repo/os/$arch\n' > "$P/etc/pacman.d/mirrorlist"
printf '# dead mirror\nServer = https://old.example.com/arch/$repo\n' > "$P/etc/pacman.d/mirrorlist-old"
printf 'db\n' > "$P/var/lib/pacman/sync/core.db"
printf 'db\n' > "$P/var/lib/pacman/sync/oldrepo.db"
touch -t 202001010000 "$P/var/lib/pacman/sync/oldrepo.db"
run "$P" "$W/out"
has "Repository 'oldrepo' has no index newer than 90 days" "$W/out" &&
has 'https://old.example.com/arch/$repo' "$W/out" &&
! grep -q 'upd008w' "$W/out" &&
  ok "pacman dead repo beside fresh: upd007w via Include" || { bad "pacman"; cat "$W/out"; }

P1=$W/pacman1; mkdir -p "$P1/etc" "$P1/var/lib/pacman/sync"
printf '[options]\n[core]\nServer = https://mirror.example.com/$repo/os/$arch\n' > "$P1/etc/pacman.conf"
printf 'db\n' > "$P1/var/lib/pacman/sync/core.db"
touch -t 202001010000 "$P1/var/lib/pacman/sync/core.db"
run "$P1" "$W/out"
! grep -q 'upd007w' "$W/out" &&
has '--WARN-- [upd008w] The pacman package lists were last refreshed over 90 days ago' "$W/out" &&
  ok "lone dead database: refresh, not stale" || { bad "pacman1"; cat "$W/out"; }

K=$W/apk; mkdir -p "$K/etc/apk" "$K/var/cache/apk"
printf 'https://alpine.example.com/v3.20/main\n' > "$K/etc/apk/repositories"
printf 'index\n' > "$K/var/cache/apk/APKINDEX.a1b2c3.tar.gz"
printf 'index\n' > "$K/var/cache/apk/APKINDEX.d4e5f6.tar.gz"
touch -t 202001010000 "$K/var/cache/apk/APKINDEX.d4e5f6.tar.gz"
run "$K" "$W/out"
has "[upd007w] \`APKINDEX.d4e5f6.tar.gz' is older than 90 days" "$W/out" &&
! grep -q 'a1b2c3' "$W/out" && ! grep -q 'upd008w' "$W/out" &&
  ok "apk dead index beside fresh: upd007w, no URL to name" || { bad "apk"; cat "$W/out"; }

K1=$W/apk1; mkdir -p "$K1/etc/apk" "$K1/var/cache/apk"
printf 'https://alpine.example.com/v3.20/main\n' > "$K1/etc/apk/repositories"
printf 'index\n' > "$K1/var/cache/apk/APKINDEX.d4e5f6.tar.gz"
touch -t 202001010000 "$K1/var/cache/apk/APKINDEX.d4e5f6.tar.gz"
run "$K1" "$W/out"
! grep -q 'upd007w' "$W/out" &&
has '--WARN-- [upd008w] The apk package lists were last refreshed over 90 days ago' "$W/out" &&
  ok "lone dead APKINDEX: refresh, not stale" || { bad "apk1"; cat "$W/out"; }

# an image's index that is a link is followed inside the image: one
# pointing out of it (at a file of this host) is never read, one whose
# absolute target is inside the image is read there
mkdir -p "$W/hostside"
release "$W/hostside/rel" HOST-SIDE-FILE host 'Tue, 16 Jun 2026 10:40:00 UTC' 'Wed, 17 Jun 2026 10:40:00 UTC'
printf '<repomd><timestamp>1700000000</timestamp></repomd>\n' > "$W/hostside/repomd.xml"
L=$W/links; mkdir -p "$L/etc" "$L/var/lib/apt/lists" "$L/srv/mirror" "$L/var/cache/dnf/x-0123456789abcdef/repodata"
ln -s "$W/hostside/rel" "$L/var/lib/apt/lists/evil_example_com_dists_x_InRelease"
ln -s "$W/hostside/repomd.xml" "$L/var/cache/dnf/x-0123456789abcdef/repodata/repomd.xml"
release "$L/srv/mirror/rel" Inside inside 'Tue, 16 Jun 2026 10:40:00 UTC' 'Wed, 17 Jun 2026 10:40:00 UTC'
ln -s /srv/mirror/rel "$L/var/lib/apt/lists/mirror_example_com_dists_x_InRelease"
printf 'package list\n' > "$L/var/lib/apt/lists/mirror_example_com_Packages"
run "$L" "$W/out"
! grep -q 'HOST-SIDE-FILE' "$W/out" && ! grep -q "Repository 'x'" "$W/out" &&
has '(from Inside) expired on 17 Jun 2026' "$W/out" &&
  ok "linked indexes: read inside the root, never this host's" || { bad "links"; cat "$W/out"; }

# names and fields are data: a backslash in a list file's or a cache
# directory's name is not an escape, and a Release with no Origin or
# Suite (apt-ftparchive's default) keeps every other field in place
N=$W/names; mkdir -p "$N/etc/yum.repos.d" "$N/var/lib/apt/lists" "$N/var/cache/dnf/my\\101repo-0123456789abcdef/repodata"
printf 'Date: Tue, 16 Jun 2026 10:40:00 UTC\n' > "$N/var/lib/apt/lists/repo.ex\\101mple.org_x_dists_stable_InRelease"
touch -t 202001010000 "$N/var/lib/apt/lists/repo.ex\\101mple.org_x_dists_stable_InRelease"
printf 'Date: Tue, 16 Jun 2026 10:40:00 UTC\n' > "$N/var/lib/apt/lists/fresh.example.org_x_dists_stable_InRelease"
printf '[myArepo]\nbaseurl=https://wrong.example.com/\n[my\\101repo]\nbaseurl=https://right.example.com/\n' > "$N/etc/yum.repos.d/x.repo"
printf '<repomd><timestamp>1781606400</timestamp></repomd>\n' > "$N/var/cache/dnf/my\\101repo-0123456789abcdef/repodata/repomd.xml"
run "$N" "$W/out"
has '`/var/lib/apt/lists/repo.ex\101mple.org_x_dists_stable_InRelease'"'"' (from repo.ex\101mple.org/x) published 120 days ago (dated 16 Jun 2026)' "$W/out" &&
! grep -q 'fresh.example.org' "$W/out" &&
has "Repository 'my\\101repo' (https://right.example.com/)" "$W/out" &&
  ok "names are data, empty fields stay put" || { bad "names"; cat "$W/out"; }

# a stock container image: every manager configured, no index cached
# (lists and caches cleaned at build), so there is nothing to judge
I=$W/image; mkdir -p "$I/etc/yum.repos.d" "$I/etc/zypp/repos.d" "$I/etc/apk" "$I/var/lib/apt/lists/partial" \
  "$I/var/cache/dnf" "$I/var/cache/libdnf5" "$I/var/cache/zypp/raw" "$I/var/lib/pacman/sync" "$I/var/cache/apk"
: > "$I/var/lib/apt/lists/lock"; touch -t 202001010000 "$I/var/lib/apt/lists/lock"
printf '[fedora]\nmetalink=https://mirrors.example.org/metalink?repo=fedora\n' > "$I/etc/yum.repos.d/fedora.repo"
printf '[repo-oss]\nbaseurl=http://download.example.org/oss/\n' > "$I/etc/zypp/repos.d/repo-oss.repo"
printf '[options]\n[core]\nServer = https://mirror.example.com/$repo/os/$arch\n' > "$I/etc/pacman.conf"
printf 'https://alpine.example.com/v3.20/main\n' > "$I/etc/apk/repositories"
run "$I" "$W/out"
[ -s "$W/out" ] && { bad "image"; cat "$W/out"; } ||
  ok "stock image, nothing cached: nothing said"

# dnf 5 keeps its cache in /var/cache/libdnf5: read, and a fresh one is
# a refresh
D5=$W/dnf5; mkdir -p "$D5/etc/yum.repos.d" "$D5/var/cache/libdnf5/updates-0123456789abcdef/repodata" "$D5/var/cache/libdnf5/dead-abcdef0123456789/repodata"
printf '<repomd><revision>2</revision><timestamp>1791110400</timestamp></repomd>\n' > "$D5/var/cache/libdnf5/updates-0123456789abcdef/repodata/repomd.xml"
printf '<repomd><revision>1</revision><timestamp>1781606400</timestamp></repomd>\n' > "$D5/var/cache/libdnf5/dead-abcdef0123456789/repodata/repomd.xml"
run "$D5" "$W/out"
! grep -q 'upd008w' "$W/out" &&
has "Repository 'dead' (see /etc/yum.repos.d) published 120 days ago (/var/cache/libdnf5/dead-abcdef0123456789/repodata/repomd.xml)" "$W/out" &&
! grep -q "'updates'" "$W/out" &&
  ok "dnf 5 cache read: refreshed, dead repo named" || { bad "dnf5"; cat "$W/out"; }

# rpm repositories are judged with the others from their host, by the
# newest: Fedora's release repository is frozen at GA and its updates
# repository says the release is alive (both through one metalink
# host). A host serving many publishers is split by publisher (COPR
# here), so one live project does not cover a dead one. openh264
# repositories are not judged (one codec package, changed only when
# Cisco releases), nor are local ones.
repomd() {  # repomd FILE TIMESTAMP
  mkdir -p "${1%/*}"; printf '<repomd><revision>1</revision><timestamp>%s</timestamp></repomd>\n' "$2" > "$1"
}
FG=$W/fedoragroup; C=$FG/var/cache/libdnf5; mkdir -p "$FG/etc/yum.repos.d"
cat > "$FG/etc/yum.repos.d/fedora.repo" <<'EOF'
[fedora]
metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch
[updates]
metalink=https://mirrors.fedoraproject.org/metalink?repo=updates-released-f$releasever&arch=$basearch
[fedora-cisco-openh264]
metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-cisco-openh264-$releasever&arch=$basearch
[thirdparty]
baseurl=https://rpm.example.com/el/stable/
[copr:alive]
baseurl=https://download.copr.example.org/results/someone/alive/fedora-$releasever-$basearch/
[copr:dead]
baseurl=https://download.copr.example.org/results/someone/dead/fedora-$releasever-$basearch/
[local]
baseurl=file:///srv/localrepo
EOF
repomd "$C/fedora-0123456789abcdef/repodata/repomd.xml" 1776124800
repomd "$C/updates-0123456789abcdef/repodata/repomd.xml" 1791110400
repomd "$C/fedora-cisco-openh264-0123456789abcdef/repodata/repomd.xml" 1700000000
repomd "$C/thirdparty-0123456789abcdef/repodata/repomd.xml" 1700000000
repomd "$C/copr:alive-0123456789abcdef/repodata/repomd.xml" 1791110400
repomd "$C/copr:dead-0123456789abcdef/repodata/repomd.xml" 1700000000
repomd "$C/local-0123456789abcdef/repodata/repomd.xml" 1600000000
run "$FG" "$W/out"
! grep -q "'fedora'\|'updates'\|openh264\|'local'\|copr:alive" "$W/out" &&
has "Repository 'thirdparty' (https://rpm.example.com/el/stable/) published 1064 days ago" "$W/out" &&
has "Repository 'copr:dead'" "$W/out" &&
[ "`grep -c 'upd007w' \"$W/out\"`" = 2 ] &&
  ok "dnf: GA repo beside fresh updates fine; openh264, local not judged; COPR split" || { bad "fedoragroup"; cat "$W/out"; }

# zypper the same: Leap's repo-oss frozen at release beside repo-update
# on the same host; an OBS home project on that host still judged on
# its own; a DVD repository not judged
LG=$W/leapgroup; C=$LG/var/cache/zypp/raw; mkdir -p "$LG/etc/zypp/repos.d"
printf '[repo-oss]\nbaseurl=http://download.opensuse.example/distribution/leap/$releasever/repo/oss/\n' > "$LG/etc/zypp/repos.d/repo-oss.repo"
printf '[repo-update]\nbaseurl=http://download.opensuse.example/update/leap/$releasever/oss\n' > "$LG/etc/zypp/repos.d/repo-update.repo"
printf '[repo-openh264]\nbaseurl=http://codecs.opensuse.example/openh264/openSUSE_Leap/\n' > "$LG/etc/zypp/repos.d/repo-openh264.repo"
printf '[home_someone]\nbaseurl=http://download.opensuse.example/repositories/home:/someone/15.6/\n' > "$LG/etc/zypp/repos.d/home_someone.repo"
printf '[dvd]\nbaseurl=cd:///?devices=/dev/sr0\n' > "$LG/etc/zypp/repos.d/dvd.repo"
repomd "$C/repo-oss/repodata/repomd.xml" 1718236800
repomd "$C/repo-update/repodata/repomd.xml" 1791110400
repomd "$C/repo-openh264/repodata/repomd.xml" 1700000000
repomd "$C/home_someone/repodata/repomd.xml" 1700000000
repomd "$C/dvd/repodata/repomd.xml" 1718236800
run "$LG" "$W/out"
! grep -q "repo-oss\|repo-update\|openh264\|'dvd'" "$W/out" &&
has "Repository 'home_someone' (http://download.opensuse.example/repositories/home:/someone/15.6/)" "$W/out" &&
  ok "zypper: repo-oss beside repo-update fine; OBS project judged alone; DVD not judged" || { bad "leapgroup"; cat "$W/out"; }

# an apt file: source (lists named _srv_...) is local: never stale
AL=$W/aptlocal; mkdir -p "$AL/etc" "$AL/var/lib/apt/lists"
printf 'Date: Tue, 16 Jun 2026 10:40:00 UTC\n' > "$AL/var/lib/apt/lists/_srv_repo_._Release"
touch -t 202001010000 "$AL/var/lib/apt/lists/_srv_repo_._Release"
printf 'package list\n' > "$AL/var/lib/apt/lists/fresh_example_com_Packages"
run "$AL" "$W/out"
! grep -q 'upd007w' "$W/out" &&
  ok "apt local file: source never stale" || { bad "aptlocal"; cat "$W/out"; }

E=$W/empty; mkdir -p "$E/etc"
run "$E" "$W/out"
[ -s "$W/out" ] && { bad "empty"; cat "$W/out"; } ||
  ok "no manager: nothing said"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
