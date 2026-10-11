#!/bin/sh
#
# tests/updates_check.sh - check_updates against trees and package managers
# of its own
#
# The package managers' answers are scripts replaying what the real ones
# printed on 7 October 2026: apt-get -s dist-upgrade on the desktop, dnf
# updateinfo list --security on Fedora 44 (dnf 5) and Rocky 9 (dnf 4),
# zypper --xmlout list-patches on Leap 16 (one patch's category made
# security), rpm -q --last kernel-core in its usual shape. Files come
# from a tree under Tiger_Sysctl_Root; Tiger_Updates_Manager picks the
# manager. A yumgpg tree carries repo files with gpgcheck off and on,
# and a dnf.conf with [main] on then off (upd005w).
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

# stand-ins: each prints a here-document
stub() { { echo '#!/bin/sh'; echo "cat <<'EOT'"; cat; echo 'EOT'; } > "$W/$1"; }
stub aptsim <<'EOF'
Inst firefox [157.0+linuxmint1] (157.0.1+linuxmint1 linuxmint:22.3/zena [amd64])
Inst libegl-mesa0 [25.2.8-0ubuntu0.24.04.2] (25.2.8-0ubuntu0.24.04.4 Ubuntu:24.04/noble-updates [amd64]) []
Inst libsoup-3.0-0 [3.4.4-5ubuntu0.5] (3.4.4-5ubuntu0.6 Ubuntu:24.04/noble-updates, Ubuntu:24.04/noble-security [amd64]) []
Inst libfreetype6 [2.13.2+dfsg-1build3] (2.13.2+dfsg-1ubuntu0.1 Ubuntu:24.04/noble-updates, Ubuntu:24.04/noble-security [amd64])
Inst libssl3 [3.0.17-1~deb12u2] (3.0.17-1~deb12u3 Debian-Security:12/stable-security [amd64])
Conf libsoup-3.0-0 (3.4.4-5ubuntu0.6 Ubuntu:24.04/noble-updates, Ubuntu:24.04/noble-security [amd64])
EOF
stub aptnone <<'EOF'
Inst firefox [157.0+linuxmint1] (157.0.1+linuxmint1 linuxmint:22.3/zena [amd64])
EOF
stub aptconf-on <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
stub aptconf-off <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "0";
EOF
stub dnf5 <<'EOF'
Name                   Type     Severity                             Package              Issued
FEDORA-2026-044e56d9ff security Moderate            tar-2:1.35-9.fc44.x86_64 2026-09-09 04:47:08
FEDORA-2026-12f3f3d569 security Important openssl-libs-1:3.5.9-1.fc44.x86_64 2026-10-03 01:09:41
FEDORA-2026-72d10c874d security Important      libevent-2.1.13-1.fc44.x86_64 2026-09-09 04:47:08
EOF
stub dnf4 <<'EOF'
RLSA-2025:23343 Moderate/Sec.  binutils-2.35.2-67.el9_7.1.x86_64
RLSA-2025:23343 Moderate/Sec.  binutils-gold-2.35.2-67.el9_7.1.x86_64
RLSA-2025:0925  Moderate/Sec.  bzip2-libs-1.0.8-10.el9_5.x86_64
EOF
printf '#!/bin/sh\necho "Error: Cache-only enabled but no cache for '"'"'fedora'"'"'" >&2\nexit 1\n' > "$W/dnfnocache"
stub zypper <<'EOF'
<?xml version='1.0'?>
<stream>
<update-status version="0.6">
<update-list>
<update kind="patch" name="openSUSE-Leap-16.0-1126" edition="1" arch="noarch" status="needed" category="recommended" severity="moderate" pkgmanager="false" restart="false" interactive="false">
<update kind="patch" name="openSUSE-Leap-16.0-500" edition="1" arch="noarch" status="needed" category="security" severity="important" pkgmanager="false" restart="false" interactive="false">
<update kind="patch" name="openSUSE-Leap-16.0-499" edition="1" arch="noarch" status="applied" category="security" severity="important" pkgmanager="false" restart="false" interactive="false">
</update-list>
</update-status>
</stream>
EOF
stub rpmnew <<'EOF'
kernel-core-6.16.10-200.fc44.x86_64           Tue 07 Oct 2026 09:12:40 BST
kernel-core-6.16.8-200.fc44.x86_64            Fri 19 Sep 2026 18:02:11 BST
EOF
stub rpmsame <<'EOF'
kernel-core-6.16.8-200.fc44.x86_64            Fri 19 Sep 2026 18:02:11 BST
EOF
printf '#!/bin/sh\necho "package kernel-core is not installed"\nexit 1\n' > "$W/rpmnone"

# enable ROOT UNIT-PATH: a timer enabled as systemctl does, with its unit
enable() { : > "$1$2"; ln -s "$2" "$1/etc/systemd/system/timers.target.wants/${2##*/}"; }
# tree NAME OSRELEASE: a root with the running kernel's release and its modules
tree() {
  r="$W/$1"; mkdir -p "$r/proc/sys/kernel" "$r/lib/modules/$2" "$r/var/lib/apt/lists" "$r/etc/systemd/system/timers.target.wants" "$r/usr/bin" "$r/lib/systemd/system" "$r/usr/lib/systemd/system"
  echo "$2" > "$r/proc/sys/kernel/osrelease"
  : > "$r/var/lib/apt/lists/archive.ubuntu.com_ubuntu_dists_noble_main_binary-amd64_Packages"
  : > "$r/var/lib/apt/lists/archive.ubuntu.com_ubuntu_dists_noble_InRelease"
}
go() {  # go NAME MANAGER setting...
  cp "$W/tigerrc.base" "$W/tigerrc"
  { echo "Tiger_Sysctl_Root='$W/$1'"; echo "Tiger_Updates_Manager='$2'"; echo "Tiger_Show_INFO_Msgs=Y"; } >> "$W/tigerrc"
  shift 2; for s; do echo "$s" >> "$W/tigerrc"; done
  ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_updates ) 2>&1 |
    awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
    tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out"
}
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -c -- "$1" "$W/out"; }
apt() { echo "Tiger_Apt_Simulate_Cmd='sh $W/$1'"; echo "Tiger_AptConfig_Cmd='sh $W/$2'"; }
dnf() { echo "Tiger_Dnf_Security_Cmd='sh $W/$1'"; echo "Tiger_Rpm_Kernel_Cmd='sh $W/$2'"; }

# apt
tree deb 6.8.0-85-generic
go deb apt "`apt aptsim aptconf-on`"
has '--FAIL-- [upd003f] 3 security updates are waiting to be installed (apt). libfreetype6, libsoup-3.0-0, libssl3. The package lists were last updated today.' &&
  ok "apt: packages from noble-security and Debian-Security counted, once each" || { bad "apt pending"; cat "$W/out"; }
has '[upd002w]' && ok "apt: no unattended-upgrades installed: upd002w" || { bad "apt auto off"; cat "$W/out"; }
: > "$W/deb/usr/bin/unattended-upgrade"; chmod 755 "$W/deb/usr/bin/unattended-upgrade"
enable "$W/deb" /lib/systemd/system/apt-daily-upgrade.timer
go deb apt "`apt aptnone aptconf-on`"
[ "`count .`" = 0 ] && ok "apt: unattended-upgrades on, nothing waiting: silent" || { bad "apt quiet"; cat "$W/out"; }
go deb apt "`apt aptnone aptconf-off`"
has '[upd002w]' && ok "apt: Unattended-Upgrade \"0\": upd002w" || { bad "apt periodic 0"; cat "$W/out"; }
tree mint 6.8.0-85-generic
enable "$W/mint" /lib/systemd/system/mintupdate-automation-upgrade.timer
go mint apt "`apt aptnone aptconf-off`"
[ "`count upd002w`" = 0 ] && ok "Linux Mint's update automation counts as automatic" || { bad "mint"; cat "$W/out"; }
rm -f "$W/mint/lib/systemd/system/mintupdate-automation-upgrade.timer"
go mint apt "`apt aptnone aptconf-off`"
has '[upd002w]' && ok "a timer link whose unit was removed does not count" || { bad "dangling timer"; cat "$W/out"; }
tree nolists 6.8.0-85-generic; rm -f "$W/nolists/var/lib/apt/lists/"*
go nolists apt "`apt aptsim aptconf-on`"
has '--INFO-- [upd004i] Security updates waiting cannot be counted: apt has no package lists' && [ "`count upd003f`" = 0 ] &&
  ok "apt without package lists: upd004i, not a count of zero" || { bad "no lists"; cat "$W/out"; }

# reboot
mkdir -p "$W/deb/run"; : > "$W/deb/run/reboot-required"
printf 'linux-image-6.8.0-86-generic\nlibc6\n' > "$W/deb/run/reboot-required.pkgs"
go deb apt "`apt aptnone aptconf-on`"
has '--WARN-- [upd001w] A reboot is needed to put the updates installed to use' && has '/run/reboot-required is there, for libc6, linux-image-6.8.0-86-generic.' &&
  ok "reboot-required, with its packages: upd001w" || { bad "reboot-required"; cat "$W/out"; }
tree arch 6.16.8-arch1-1; mv "$W/arch/lib/modules/6.16.8-arch1-1" "$W/arch/lib/modules/6.16.10-arch1-1"
go arch pacman
has 'the running kernel, 6.16.8-arch1-1, has no modules in /lib/modules any more' && ok "pacman: the running kernel's modules gone: upd001w" || { bad "arch"; cat "$W/out"; }
mkdir -p "$W/arch/run"; : > "$W/arch/.dockerenv"
go arch pacman
[ "`count upd001w`" = 0 ] && ok "a container: no reboot finding" || { bad "container"; cat "$W/out"; }

# dnf and zypper
tree fed 6.16.8-200.fc44.x86_64
go fed dnf "`dnf dnf5 rpmnew`"
has '--FAIL-- [upd003f] 3 security updates are waiting to be installed (dnf). libevent-2.1.13-1.fc44.x86_64, openssl-libs-1:3.5.9-1.fc44.x86_64, tar-2:1.35-9.fc44.x86_64.' &&
  ok "dnf 5's layout: three packages" || { bad "dnf5"; cat "$W/out"; }
has 'kernel 6.16.10-200.fc44.x86_64 was installed last, and 6.16.8-200.fc44.x86_64 is running' && ok "dnf: a newer kernel-core installed: upd001w" || { bad "rpm kernel"; cat "$W/out"; }
has '[upd002w]' && ok "dnf: no dnf-automatic: upd002w" || { bad "dnf auto"; cat "$W/out"; }
enable "$W/fed" /usr/lib/systemd/system/dnf-automatic.timer
mkdir -p "$W/fed/etc/dnf"; printf '[commands]\napply_updates = no\n' > "$W/fed/etc/dnf/automatic.conf"
go fed dnf "`dnf dnf4 rpmsame`"
has '3 security updates are waiting to be installed (dnf). binutils-2.35.2-67.el9_7.1.x86_64, binutils-gold-2.35.2-67.el9_7.1.x86_64, bzip2-libs-1.0.8-10.el9_5.x86_64.' &&
  ok "dnf 4's layout: three packages" || { bad "dnf4"; cat "$W/out"; }
[ "`count upd001w`" = 0 ] && ok "dnf: the newest kernel is running: no reboot" || { bad "rpm same"; cat "$W/out"; }
has '[upd002w]' && ok "dnf-automatic.timer with apply_updates = no only downloads: upd002w" || { bad "apply no"; cat "$W/out"; }
mkdir -p "$W/fed/etc/dnf/dnf5-plugins"; printf '[commands]\napply_updates = yes\n' > "$W/fed/etc/dnf/dnf5-plugins/automatic.conf"
go fed dnf "`dnf dnfnocache rpmnone`"
[ "`count upd002w`" = 0 ] && ok "dnf5's automatic.conf with apply_updates = yes: automatic" || { bad "apply yes"; cat "$W/out"; }
has "[upd004i] Security updates waiting cannot be counted: dnf could not answer from its cache (Error: Cache-only enabled but no cache for 'fedora')." && [ "`count upd001w`" = 0 ] &&
  ok "dnf without a cache: upd004i; rpm without kernel-core: no reboot guessed" || { bad "dnf no cache"; cat "$W/out"; }
# gpgcheck: a repo file turning signing off, a signed one, a [main]
# default on, then off
tree yumgpg 6.16.8-200.fc44.x86_64
mkdir -p "$W/yumgpg/etc/yum.repos.d" "$W/yumgpg/etc/dnf"
printf '[fedora]\nname=Fedora\nbaseurl=https://example.invalid/\ngpgcheck=0\n' > "$W/yumgpg/etc/yum.repos.d/fedora.repo"
printf '[updates]\nname=Updates\nbaseurl=https://example.invalid/\ngpgcheck=1\ngpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora\n' > "$W/yumgpg/etc/yum.repos.d/updates.repo"
printf '[main]\ngpgcheck=1\n' > "$W/yumgpg/etc/dnf/dnf.conf"
go yumgpg dnf "`dnf dnf5 rpmnew`"
has "Repository 'fedora' installs unsigned packages (gpgcheck off in /etc/yum.repos.d/fedora.repo)." && [ "`count upd005w`" = 1 ] &&
  ok "a repo with gpgcheck=0: upd005w, and only it" || { bad "gpgcheck off"; cat "$W/out"; }
printf '[main]\ngpgcheck=0\n' > "$W/yumgpg/etc/dnf/dnf.conf"
go yumgpg dnf "`dnf dnf5 rpmnew`"
has 'The [main] default in /etc/dnf/dnf.conf turns package signing off' && [ "`count upd005w`" = 2 ] &&
  ok "[main] gpgcheck=0: the default finding plus the repo one" || { bad "gpgcheck main"; cat "$W/out"; }
tree suse 6.4.0-150600.23.25-default
go suse zypper "Tiger_Zypper_Security_Cmd='sh $W/zypper'"
has '--FAIL-- [upd003f] 1 security updates are waiting to be installed (zypper). openSUSE-Leap-16.0-500.' && [ "`count upd002w`" = 0 ] &&
  ok "zypper: needed security patches only; nothing said about automatic updates" || { bad "zypper"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
