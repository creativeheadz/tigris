#!/bin/sh
#
# tests/storage_check.sh - check_storage against /proc, /sys and /etc trees
#
# Mount tables, swap lists, block devices (dm-crypt under LVM, as
# /sys/class/block shows them), batteries (a laptop's, and a wireless
# mouse's, which must not count), core_pattern, limits and modprobe files,
# all under Tiger_Sysctl_Root.
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

# tree NAME: /proc and /sys skeletons; the mount table on stdin
tree() {
  r="$W/$1"; mkdir -p "$r/proc/sys/kernel" "$r/sys/class/block" "$r/sys/class/power_supply" "$r/etc/security/limits.d" "$r/dev/mapper"
  cat > "$r/proc/mounts"
  printf 'Filename\tType\tSize\tUsed\tPriority\n' > "$r/proc/swaps"
  echo '|/usr/lib/systemd/systemd-coredump %P %u %g %s %t %c %h' > "$r/proc/sys/kernel/core_pattern"
}
blockdev() { mkdir -p "$W/$1/sys/class/block/$2"; }       # blockdev TREE NAME
dm() {  # dm TREE NAME UUID [SLAVE]
  mkdir -p "$W/$1/sys/class/block/$2/dm" "$W/$1/sys/class/block/$2/slaves"; echo "$3" > "$W/$1/sys/class/block/$2/dm/uuid"
  [ -n "$4" ] && mkdir -p "$W/$1/sys/class/block/$2/slaves/$4"; :
}
battery() {  # battery TREE NAME [SCOPE]
  b="$W/$1/sys/class/power_supply/$2"; mkdir -p "$b"; echo Battery > "$b/type"; [ -n "$3" ] && echo "$3" > "$b/scope"; :
}
go() {  # go TREE setting...
  cp "$W/tigerrc.base" "$W/tigerrc"
  { echo "Tiger_Sysctl_Root='$W/$1'"; echo "Tiger_Show_INFO_Msgs=Y"; } >> "$W/tigerrc"
  shift; for s; do echo "$s" >> "$W/tigerrc"; done
  ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_storage ) 2>&1 |
    awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
    tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out"
}
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -F -c -- "$1" "$W/out"; }

# the desktop: ext4 on NVMe, /dev/shm without noexec, a mouse's battery
tree desk <<'EOF'
/dev/nvme0n1p2 / ext4 rw,relatime,errors=remount-ro 0 0
/dev/nvme0n1p1 /boot/efi vfat rw,relatime 0 0
/dev/nvme1n1p1 /srv/data ext4 rw,nosuid,nodev,relatime 0 0
tmpfs /dev/shm tmpfs rw,nosuid,nodev,inode64 0 0
/dev/loop3 /snap/core22/2045 squashfs ro,nodev,relatime 0 0
EOF
blockdev desk nvme0n1p2; blockdev desk nvme1n1p1; battery desk hidpp_battery_0 Device
go desk
has '--INFO-- [stor003i] /tmp is part of the root file system' && has '--INFO-- [stor002i] /dev/shm is mounted without noexec.' &&
  [ "`count stor001w`" = 0 ] && ok "the desktop: /tmp not separate, /dev/shm without noexec (INFO), nosuid and nodev there" || { bad "desk mounts"; cat "$W/out"; }
has '--INFO-- [stor005i] Some local file systems are not encrypted' && has 'Not encrypted: / (/dev/nvme0n1p2), /srv/data (/dev/nvme1n1p1).' &&
  [ "`count stor004w`" = 0 ] && ok "the desktop: unencrypted disks INFO, /boot and snaps left out, a mouse's battery is not a laptop's" || { bad "desk crypt"; cat "$W/out"; }
[ "`count stor007w`" = 0 ] && ok "core dumps to systemd-coredump: nothing" || { bad "coredump pipe"; cat "$W/out"; }

# A laptop: the same disks, its own battery
cp -r "$W/desk" "$W/laptop"; battery laptop BAT0
go laptop
has '--WARN-- [stor004w] This machine runs on a battery' && ok "a laptop's own battery: stor004w" || { bad "laptop"; cat "$W/out"; }

# LVM on LUKS, a tmpfs /tmp without nosuid, a plain swap partition
tree luks <<'EOF'
/dev/mapper/vg-root / ext4 rw,relatime 0 0
tmpfs /tmp tmpfs rw,nodev,noexec 0 0
tmpfs /dev/shm tmpfs rw,nosuid,nodev,noexec 0 0
EOF
ln -s ../dm-1 "$W/luks/dev/mapper/vg-root"; : > "$W/luks/dev/dm-1"
dm luks dm-1 LVM-abcdef dm-0; dm luks dm-0 CRYPT-LUKS2-0123456789abcdef-luks-root nvme0n1p3; blockdev luks nvme0n1p3; blockdev luks nvme0n1p4
battery luks BAT0
printf '/dev/nvme0n1p4 partition 8388604 0 -2\n/dev/zram0 partition 4194300 0 100\n' >> "$W/luks/proc/swaps"
go luks
[ "`count stor004w`" = 0 ] && [ "`count stor005i`" = 0 ] &&
  ok "LVM on LUKS: encrypted, found through the slaves" || { bad "luks"; cat "$W/out"; }
has '--WARN-- [stor001w] /tmp is mounted without nosuid' && ok "a tmpfs /tmp without nosuid: stor001w" || { bad "tmp nosuid"; cat "$W/out"; }
has '--WARN-- [stor006w] The root file system is encrypted but swap is not' && has 'Swap: /dev/nvme0n1p4.' && [ "`count stor006w`" = 1 ] &&
  ok "a plain swap partition under an encrypted root: stor006w; zram left out" || { bad "swap"; cat "$W/out"; }
printf 'Filename\tType\tSize\tUsed\tPriority\n/swapfile file 2097148 0 -2\n' > "$W/luks/proc/swaps"
go luks
[ "`count stor006w`" = 0 ] && ok "a swap file on the encrypted root: nothing" || { bad "swapfile"; cat "$W/out"; }

# Core dumps as files, then limited
echo core > "$W/desk/proc/sys/kernel/core_pattern"
go desk
has '--WARN-- [stor007w] A program that crashes writes its memory to a core file' && ok "core_pattern \"core\", no limit: stor007w" || { bad "core"; cat "$W/out"; }
echo '*    hard    core    0' > "$W/desk/etc/security/limits.d/10-core.conf"
go desk
[ "`count stor007w`" = 0 ] && ok "'* hard core 0' in limits.d: nothing" || { bad "core limit"; cat "$W/out"; }

# USB storage, when the policy says none
go desk "Tiger_Storage_NoUSB=Y"
has '--WARN-- [stor008w] USB storage can be used' && ok "Tiger_Storage_NoUSB=Y, nothing blocks it: stor008w" || { bad "usb"; cat "$W/out"; }
mkdir -p "$W/desk/etc/modprobe.d"; printf 'install usb-storage /bin/false\nblacklist usb-storage\n' > "$W/desk/etc/modprobe.d/usb.conf"
go desk "Tiger_Storage_NoUSB=Y"
has '--WARN-- [stor008w] USB storage can be used' && ok "uas not blocked: stor008w still" || { bad "usb uas"; cat "$W/out"; }
printf 'install uas /bin/false\nblacklist uas\n' >> "$W/desk/etc/modprobe.d/usb.conf"
go desk "Tiger_Storage_NoUSB=Y"
[ "`count stor008w`" = 0 ] && ok "usb-storage and uas blocked in modprobe.d: nothing" || { bad "usb blocked"; cat "$W/out"; }
rm -f "$W/desk/etc/modprobe.d/usb.conf"; go desk
[ "`count stor008w`" = 0 ] && ok "by default USB storage is not looked at" || { bad "usb default"; cat "$W/out"; }

# New devices unauthorized by default counts as no-USB enforcement
mkdir -p "$W/desk/sys/module/usbcore/parameters"; echo 0 > "$W/desk/sys/module/usbcore/parameters/authorized_default"
go desk "Tiger_Storage_NoUSB=Y"
[ "`count stor008w`" = 0 ] && ok "authorized_default=0, no modprobe: nothing" || { bad "usb authdefault"; cat "$W/out"; }
echo 1 > "$W/desk/sys/module/usbcore/parameters/authorized_default"
go desk "Tiger_Storage_NoUSB=Y"
has '--WARN-- [stor008w] USB storage can be used' && ok "authorized_default=1: stor008w" || { bad "usb authdefault1"; cat "$W/out"; }
rm -rf "$W/desk/sys/module"

# A storage device connected although the policy says none
mkdir -p "$W/desk/etc/modprobe.d" "$W/desk/sys/bus/usb/devices/1-2:1.0" "$W/desk/sys/bus/usb/devices/1-3:1.0"
printf 'blacklist usb-storage\nblacklist uas\n' > "$W/desk/etc/modprobe.d/usb.conf"
echo 08 > "$W/desk/sys/bus/usb/devices/1-2:1.0/bInterfaceClass"; echo "Ultra Stick" > "$W/desk/sys/bus/usb/devices/1-2:1.0/product"
echo 03 > "$W/desk/sys/bus/usb/devices/1-3:1.0/bInterfaceClass"
go desk "Tiger_Storage_NoUSB=Y"
has "--WARN-- [stor008w] A USB storage device ('Ultra Stick') is connected" && [ "`count stor008w`" = 1 ] &&
  ok "a connected stick, blocked on paper: stor008w names it; the keyboard is not storage" || { bad "usb connected"; cat "$W/out"; }
go desk
[ "`count stor008w`" = 0 ] && ok "no policy: a connected stick is not judged" || { bad "usb connected default"; cat "$W/out"; }
rm -rf "$W/desk/sys/bus" "$W/desk/etc/modprobe.d/usb.conf"

# USB authorization: USBGuard running, dead, and wide open
tree guard <<'EOF'
/dev/nvme0n1p2 / ext4 rw,relatime 0 0
EOF
blockdev guard nvme0n1p2
mkdir -p "$W/guard/proc/1" "$W/guard/etc/usbguard"
echo usbguard-daemon > "$W/guard/proc/1/comm"
printf 'allow id 1234:5678 serial "ABC"\nblock\n' > "$W/guard/etc/usbguard/rules.conf"
go guard
has '--INFO-- [stor014i] USBGuard authorizes USB devices (2 rules in /etc/usbguard/rules.conf).' &&
  [ "`count stor015w`" = 0 ] && [ "`count stor016w`" = 0 ] &&
  ok "USBGuard running with scoped rules: stor014i" || { bad "guard"; cat "$W/out"; }
cp -r "$W/guard" "$W/dead"; rm -rf "$W/dead/proc/1"
go dead
has '--WARN-- [stor015w] USBGuard is configured but its daemon is not running' && [ "`count stor016w`" = 0 ] &&
  ok "USBGuard configured and dead: stor015w" || { bad "dead"; cat "$W/out"; }
printf '# everything\nallow\n' > "$W/dead/etc/usbguard/rules.conf"
go dead
has "--WARN-- [stor016w] USBGuard allows every USB device (a bare 'allow' in /etc/usbguard/rules.conf)" &&
  has '--WARN-- [stor015w]' &&
  ok "bare allow with a dead daemon: stor016w and stor015w" || { bad "allow"; cat "$W/out"; }
printf 'RuleFile=/etc/usbguard/custom.rules\n' > "$W/dead/etc/usbguard/usbguard-daemon.conf"
printf 'allow\n' > "$W/dead/etc/usbguard/custom.rules"
printf 'block\n' > "$W/dead/etc/usbguard/rules.conf"
go dead
has "--WARN-- [stor016w] USBGuard allows every USB device (a bare 'allow' in /etc/usbguard/custom.rules)" &&
  ok "RuleFile elsewhere: that file is judged" || { bad "rulefile"; cat "$W/out"; }

# FireWire storage, when the policy says none
go desk "Tiger_Storage_NoFireWire=Y"
has '--WARN-- [stor010w] FireWire can be used' && ok "Tiger_Storage_NoFireWire=Y, nothing blocks it: stor010w" || { bad "firewire"; cat "$W/out"; }
printf 'blacklist firewire-core\nblacklist firewire-ohci\n' > "$W/desk/etc/modprobe.d/firewire.conf"
go desk "Tiger_Storage_NoFireWire=Y"
[ "`count stor010w`" = 0 ] && ok "FireWire blacklisted in modprobe.d: nothing" || { bad "firewire blocked"; cat "$W/out"; }
rm -f "$W/desk/etc/modprobe.d/firewire.conf"; go desk
[ "`count stor010w`" = 0 ] && ok "by default FireWire storage is not looked at" || { bad "firewire default"; cat "$W/out"; }

# A container
tree ctr <<'EOF'
overlay / overlay rw,relatime,lowerdir=/x 0 0
EOF
go ctr
[ "`count .`" = 0 ] && ok "a container (overlay root): nothing said" || { bad "container"; cat "$W/out"; }

# Offline roots (TIGRIS_ROOT, as tigris --root sets it): what they set up at
# boot. A: /tmp in fstab without nodev, no crypttab, no core_pattern (the
# kernel's "core") and no limit. B: /tmp from systemd's tmp.mount, a
# crypttab and a swap partition outside it, a core_pattern piped to a
# handler, usb-storage blacklisted.
offline() {
  cp "$W/tigerrc.base" "$W/tigerrc" 2>/dev/null || true
  { echo "Tiger_Show_INFO_Msgs=Y"; echo "Tiger_Storage_NoUSB=Y"; echo "Tiger_Storage_NoFireWire=Y"; } >> "$W/tigerrc"
  ( cd "$W" && TIGRIS_ROOT=$1 TIGERHOMEDIR=$W sh ./systems/Linux/2/check_storage ) 2>&1 < /dev/null |
    awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
    tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out"
}
A=$W/rootA B=$W/rootB
mkdir -p "$A/etc" "$B/etc/sysctl.d" "$B/etc/modprobe.d" "$B/usr/lib/systemd/system/local-fs.target.wants"
cat > "$A/etc/fstab" <<'EOF'
UUID=1111 / ext4 defaults 0 1
tmpfs /tmp tmpfs nosuid,size=2G 0 0
EOF
cat > "$B/etc/fstab" <<'EOF'
/dev/mapper/root / ext4 defaults 0 1
/dev/sda3 none swap sw 0 0
/dev/mapper/cswap none swap sw 0 0
EOF
printf 'root UUID=2222 none luks\ncswap /dev/sda4 /dev/urandom swap\n' > "$B/etc/crypttab"
printf '[Mount]\nWhat=tmpfs\nWhere=/tmp\nType=tmpfs\nOptions=mode=1777,strictatime,nosuid,nodev,size=50%%\n' > "$B/usr/lib/systemd/system/tmp.mount"
ln -s ../tmp.mount "$B/usr/lib/systemd/system/local-fs.target.wants/tmp.mount"
echo 'kernel.core_pattern=|/usr/lib/systemd/systemd-coredump %P %u %g %s %t' > "$B/etc/sysctl.d/50-coredump.conf"
printf 'blacklist usb-storage\nblacklist uas\n' > "$B/etc/modprobe.d/usb.conf"
printf 'blacklist firewire-core\nblacklist firewire-ohci\n' > "$B/etc/modprobe.d/firewire.conf"

offline "$A"
has '[stor001w] /tmp is mounted without nodev' && ok "offline root: /tmp in fstab without nodev: stor001w" || { bad "offline stor001w"; cat "$W/out"; }
has '[stor009i] /etc/crypttab names no encrypted device' && ok "offline root: no crypttab: stor009i" || { bad "offline stor009i"; cat "$W/out"; }
has "[stor007w] A program that crashes" && has "the kernel's default: nothing in its sysctl.d sets it" &&
  ok "offline root: core_pattern unset (the kernel's core) and no limit: stor007w" || { bad "offline stor007w"; cat "$W/out"; }
has '[stor008w]' && ok "offline root: usb-storage not blacklisted, with the policy on: stor008w" || { bad "offline stor008w"; cat "$W/out"; }
has '[stor010w]' && ok "offline root: FireWire not blacklisted, with the policy on: stor010w" || { bad "offline stor010w"; cat "$W/out"; }

offline "$B"
[ "`count 'stor001w'`" = 0 ] && has "[stor002i] /tmp is mounted without noexec" && has "by systemd's tmp.mount" &&
  ok "offline root: /tmp from tmp.mount, nosuid and nodev: only stor002i" || { bad "offline tmp.mount"; cat "$W/out"; }
has '[stor006w]' && has 'Swap: /dev/sda3' && [ "`count 'cswap'`" = 0 ] &&
  ok "offline root: a swap partition outside crypttab: stor006w; the crypttab one is fine" || { bad "offline stor006w"; cat "$W/out"; }
[ "`count stor007w`" = 0 ] && [ "`count stor008w`" = 0 ] && [ "`count stor009i`" = 0 ] && [ "`count stor010w`" = 0 ] && ok "offline root: a core handler, USB and FireWire blacklisted, a crypttab: nothing" || { bad "offline B"; cat "$W/out"; }
U=$W/rootC
mkdir -p "$U/etc" "$U/etc/modprobe.d" "$U/etc/usbguard"
printf 'UUID=1111 / ext4 defaults 0 1\n' > "$U/etc/fstab"
printf 'options usbcore authorized_default=0\n' > "$U/etc/modprobe.d/usb.conf"
printf 'allow id 1234:5678\nallow\n' > "$U/etc/usbguard/rules.conf"
offline "$U"
[ "`count stor008w`" = 0 ] && has '--WARN-- [stor016w]' &&
  [ "`count stor014i`" = 0 ] && [ "`count stor015w`" = 0 ] &&
  ok "offline: authorized_default counts, bare allow judged, running state not" || { bad "offline C"; cat "$W/out"; }

# Second phase: LVM metadata, ACLs past the mode, the locate database
L=$W/second
mkdir -p "$L/etc/lvm/backup" "$L/etc" "$L/var/lib/mlocate"
cat > "$L/etc/lvm/backup/vg0" <<'EOF'
contents = "Text Format Volume Group"
version = 1
description = "created by test"
vg0 {
	id = "abc123"
	physical_volumes {
		pv0 {
			id = "def456"
		}
	}
	logical_volumes {
		root {
			id = "ghi789"
		}
		swap {
			id = "jkl012"
		}
	}
}
EOF
printf 'root:!:1:0:::::\n' > "$L/etc/shadow"
chmod 600 "$L/etc/shadow"
mkdir -p "$L/etc/sudoers.d" "$L/etc/ssh"
printf 'ops ALL=(ALL) ALL\n' > "$L/etc/sudoers.d/90-ops"; chmod 440 "$L/etc/sudoers.d/90-ops"
printf 'key\n' > "$L/etc/ssh/ssh_host_ed25519_key"; chmod 600 "$L/etc/ssh/ssh_host_ed25519_key"
printf 'mlocate-bytes' > "$L/var/lib/mlocate/mlocate.db"
chmod 644 "$L/var/lib/mlocate/mlocate.db"
offline "$L"
has '[stor011i] LVM volume group vg0 holds logical volumes root, swap.' && ok "LVM metadata: stor011i names the group and its volumes" || { bad "lvm"; cat "$W/out"; }
has '[stor013w]' && has '`/var/lib/mlocate/mlocate.db'"'"' is readable by anyone' "$W/out" &&
  ok "a world-readable locate database: stor013w" || { bad "locate"; cat "$W/out"; }
! grep -q 'stor012w' "$W/out" &&
  ok "no ACLs on the fixtures: no stor012w" || { bad "acl quiet"; cat "$W/out"; }

# A getfacl that reports an extra entry on shadow, bare modes else
mkdir -p "$W/fakebin"
cat > "$W/fakebin/getfacl" <<'EOF'
#!/bin/sh
eval "f=\${$#}"
case "$f" in
  *shadow|*/sudoers.d/90-ops|*/ssh_host_ed25519_key) printf '# file: x\n# owner: root\n# group: root\nuser::r--\nuser:adm:r--\ngroup::r--\nmask::r--\nother::---\n' ;;
  *) printf '# file: other\n# owner: root\n# group: root\nuser::rw-\ngroup::r--\nother::r--\n' ;;
esac
EOF
chmod 755 "$W/fakebin/getfacl"
cp "$W/tigerrc.base" "$W/tigerrc"
{ echo "Tiger_Show_INFO_Msgs=Y"; echo "Tiger_Storage_NoUSB=Y"; echo "Tiger_Storage_NoFireWire=Y"; echo "Tiger_Getfacl='$W/fakebin/getfacl'"; } >> "$W/tigerrc"
( cd "$W" && TIGRIS_ROOT="$L" TIGERHOMEDIR=$W sh ./systems/Linux/2/check_storage ) 2>&1 < /dev/null |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out"
has '[stor012w]' && has '`/etc/shadow'"'"' grants user:adm:r-- beyond its mode' "$W/out" &&
  ok "an ACL past the mode: stor012w names file and entry" || { bad "acl"; cat "$W/out"; }
# sudoers.d and the SSH host keys are looked at too (a typo once kept
# them out of the list)
has '`/etc/sudoers.d/90-ops'"'"' grants user:adm:r--' "$W/out" &&
has '`/etc/ssh/ssh_host_ed25519_key'"'"' grants user:adm:r--' "$W/out" &&
  ok "sudoers.d files and SSH host keys: stor012w" || { bad "acl sudoers.d and host keys"; cat "$W/out"; }

T=$W/tight2
mkdir -p "$T/etc" "$T/var/lib/mlocate"
printf 'root:!:1:0:::::\n' > "$T/etc/shadow"
chmod 600 "$T/etc/shadow"
printf 'mlocate-bytes' > "$T/var/lib/mlocate/mlocate.db"
chmod 600 "$T/var/lib/mlocate/mlocate.db"
offline "$T"
! grep -q 'stor011i\|stor012w\|stor013w' "$W/out" &&
  ok "no LVM, no ACLs, a guarded database: nothing" || { bad "tight2"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
