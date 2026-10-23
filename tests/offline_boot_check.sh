#!/bin/sh
#
# tests/offline_boot_check.sh - the boot checks on an offline root
#
# Two roots run with the boot and single-user checks on. The first has
# a group- and world-readable lilo.conf with no password and a
# group- and world-readable grub.cfg that does set one: every leg must
# be reported by the root's own paths. It boots with systemd: its
# rescue.service runs sulogin and must pass, its emergency.service has a
# drop-in that starts a bare shell and must be reported, and the sysvinit
# inittab left behind (no sulogin in it) must not be read. The second
# root has no boot loader configuration at all but an inittab without
# sulogin: the missing configuration and the missing sulogin line must
# both be reported. check_lilo needs root (the boot loader's
# configuration is root's): as a user it must be skipped as such, and as
# root its findings are checked too. CI runs this both ways.
# check_single then runs alone on smaller roots: busybox's inittab, other
# distributions' sulogin lines, lilo passwords, sulogin forced open with
# root locked (and not locked), a masked unit; and on this host, whatever
# its architecture (it once did nothing unless that was i?86).
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
uid=`id -u`
[ "$uid" = 0 ] && chown -R 0:0 "$W"

R=$W/img
U=$uid; G=`id -g`
[ "$uid" = 0 ] && { U=4242; G=4242; }
mkdir -p "$R/etc" "$R/boot/grub"
printf 'root:x:0:0:root:/root:/bin/bash\nmilo:x:%s:%s:Milo:/home/milo:/bin/bash\n' "$U" "$G" > "$R/etc/passwd"
printf 'root:x:0:\ncrew:x:%s:\n' "$G" > "$R/etc/group"
printf '# lilo\nimage=/boot/vmlinuz\n' > "$R/etc/lilo.conf"
chmod 644 "$R/etc/lilo.conf"
printf 'password s3cret\nmenuentry x {\n}\n' > "$R/boot/grub/grub.cfg"
chmod 644 "$R/boot/grub/grub.cfg"
# systemd: its units as systemd 240 and later ship them, and a drop-in
# that hands emergency mode a shell; the inittab sysvinit left behind
mkdir -p "$R/sbin" "$R/usr/lib/systemd/system" "$R/etc/systemd/system/emergency.service.d"
ln -s ../usr/lib/systemd/systemd "$R/sbin/init"
printf '[Unit]\nDescription=Rescue Shell\n\n[Service]\nEnvironment=HOME=/root\nExecStart=-/usr/lib/systemd/systemd-sulogin-shell rescue\nType=idle\n' > "$R/usr/lib/systemd/system/rescue.service"
printf '[Unit]\nDescription=Emergency Shell\n\n[Service]\nExecStart=-/usr/lib/systemd/systemd-sulogin-shell emergency\nType=idle\n' > "$R/usr/lib/systemd/system/emergency.service"
printf '[Service]\nExecStart=\nExecStart=-/bin/sh\n' > "$R/etc/systemd/system/emergency.service.d/override.conf"
printf 'id:2:initdefault:\nsi::sysinit:/etc/init.d/rcS\n' > "$R/etc/inittab"
[ "$uid" = 0 ] && chown -R "$U:$G" "$R"

S=$W/sysv
mkdir -p "$S/etc"
printf 'id:3:initdefault:\nsi::sysinit:/etc/init.d/rcS\n' > "$S/etc/inittab"

{
  sed -n 's/^\(Tigris_Check_[A-Z_]*\)=.*/\1=N/p' "$W/tigris.conf"
  for c in BOOT SINGLE SYSTEM; do echo "Tigris_Check_$c=Y"; done
} > "$W/profiles/boot"
chmod 644 "$W/profiles/boot"

( cd "$W" && sh ./tigris -q --profile boot --root "$R" ) > "$W/out" 2>&1
json=`ls "$W"/log/*.jsonl 2>/dev/null | head -1`
[ -n "$json" ] || { echo "FAIL no report:"; cat "$W/out"; exit 1; }
has() { grep -q -- "$1" "$json"; }

if [ "$uid" = 0 ]; then
  has '"id":"boot001w".*lilo.conf has group permissions' &&
    ok "a group-readable lilo.conf: boot001w" || bad "boot001w"
  has '"id":"boot002f".*lilo.conf has other permissions' &&
    ok "a world-readable lilo.conf: boot002f" || bad "boot002f"
  has '"id":"boot006w".*lilo is not configured with a password' &&
    ok "no lilo password: boot006w" || bad "boot006w"
  has '"id":"boot003w".*Grub bootloader configuration file /boot/grub/grub.cfg has group permissions' &&
    ok "a group-readable grub.cfg: boot003w" || bad "boot003w"
  has '"id":"boot004f".*Grub bootloader configuration file /boot/grub/grub.cfg has world readable permissions' &&
    ok "a world-readable grub.cfg: boot004f" || bad "boot004f"
else
  has '{"type":"skip","check":"check_lilo","reason":"needs root"}' &&
    ok "as a user, check_lilo is skipped for root (its findings are checked as root)" || bad "check_lilo as a user"
fi
has '"id":"sum002f".*emergency.service starts without sulogin.*(-/bin/sh)' &&
  ok "a drop-in that starts emergency mode as a bare shell: sum002f" || bad "sum002f"
grep '"type":"finding"' "$json" | grep 'sum00[23]' | grep -q 'rescue.service' &&
  bad "rescue.service, stock (systemd-sulogin-shell), was reported" ||
  ok "rescue.service, stock (systemd-sulogin-shell), passes"
grep '"type":"finding"' "$json" | grep -q 'sum001f' &&
  bad "the inittab was read though systemd is the root's init" ||
  ok "under systemd the inittab sysvinit left behind is not read"
grep '"type":"finding"' "$json" | grep -q "$R" && bad "a finding names the root's directory on this host" ||
  ok "findings name the root's own paths, never where it is on this host"
sh "$W/tests/schema_check.sh" "$json" > "$W/schema.out" 2>&1 && ok "the report validates" ||
  { grep -q SKIP "$W/schema.out" && ok "(schema not checked: $(cat "$W/schema.out"))" || { bad "schema"; cat "$W/schema.out"; }; }

# Second run, a report name apart: report names only resolve a second.
sleep 2
( cd "$W" && sh ./tigris -q --profile boot --root "$S" ) > "$W/out2" 2>&1
json2=`ls -t "$W"/log/*.jsonl 2>/dev/null | head -1`
[ -n "$json2" ] && [ "$json2" != "$json" ] || { echo "FAIL no second report:"; cat "$W/out2"; exit 1; }
if [ "$uid" = 0 ]; then
  grep -q '"id":"boot005w".*Could not access' "$json2" &&
    ok "no boot loader configuration at all: boot005w" || bad "boot005w"
fi
grep -q '"id":"sum001f".*Recommend addition to /etc/inittab:  ~~:S:wait:/sbin/sulogin' "$json2" &&
  ok "an inittab without sulogin: sum001f" || bad "sum001f"
grep '"type":"finding"' "$json2" | grep -q "$S" && bad "a finding names the second root's directory on this host" ||
  ok "the second report names the root's own paths too"
sh "$W/tests/schema_check.sh" "$json2" > "$W/schema2.out" 2>&1 && ok "the second report validates" ||
  { grep -q SKIP "$W/schema2.out" && ok "(schema not checked: $(cat "$W/schema2.out"))" || { bad "schema2"; cat "$W/schema2.out"; }; }

# check_single alone, ROOT by ROOT: its findings, one a line
AWK=`command -v awk`
single() {
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/Linux/2/check_single ) 2>&1 |
    $AWK '/^--[A-Z]+-- \[/ { if (s != "") print s; s = $0; next } /^ / && s != "" { sub(/^ +/, " "); s = s $0; next } END { if (s != "") print s }'
}
sysv() {  # sysv DIR INITTAB-LINE...: a System V root
  mkdir -p "$W/$1/etc"; d=$1; shift
  { echo 'id:2:initdefault:'; for l; do echo "$l"; done; } > "$W/$d/etc/inittab"
}
sysv bb; printf '::sysinit:/sbin/openrc sysinit\ntty1::respawn:/sbin/getty 38400 tty1\n' > "$W/bb/etc/inittab"
[ -z "`single "$W/bb"`" ] && ok "busybox's inittab (no runlevels) is not judged as System V's" || bad "busybox inittab: `single "$W/bb"`"
sysv gentoo 'su0:S:wait:/sbin/rc single' 'su1:S:wait:/sbin/sulogin'
[ -z "`single "$W/gentoo"`" ] && ok "Gentoo's su1:S:wait:/sbin/sulogin counts" || bad "Gentoo sulogin: `single "$W/gentoo"`"
sysv lilo; printf 'image=/boot/vmlinuz\n# password=old\n' > "$W/lilo/etc/lilo.conf"
single "$W/lilo" | grep -q 'sum001f' && ok "a lilo.conf without a password no longer hides a missing sulogin" || bad "lilo without password"
printf 'image=/boot/vmlinuz\n  password = s3cret\n' > "$W/lilo/etc/lilo.conf"
[ -z "`single "$W/lilo"`" ] && ok "a lilo password stands in for sulogin" || bad "lilo password: `single "$W/lilo"`"
sysv force '~~:S:wait:/sbin/sulogin --force'
printf 'root:*:19000:0:99999:7:::\n' > "$W/force/etc/shadow"
single "$W/force" | grep -q 'WARN.*sum003w.*/etc/inittab runs sulogin --force' &&
  ok "sulogin --force in the inittab with root locked: sum003w" || bad "inittab --force: `single "$W/force"`"
printf 'root:$6$salt$hash:19000:0:99999:7:::\n' > "$W/force/etc/shadow"
[ -z "`single "$W/force"`" ] && ok "sulogin --force with root's password set asks for it: quiet" || bad "inittab --force, root unlocked"
# systemd: sulogin forced open by a drop-in, and a masked unit
sd=$W/sd; mkdir -p "$sd/sbin" "$sd/etc/systemd/system/rescue.service.d" "$sd/usr/lib/systemd/system"
ln -s ../usr/lib/systemd/systemd "$sd/sbin/init"
cp "$R/usr/lib/systemd/system/rescue.service" "$sd/usr/lib/systemd/system/"
printf '[Service]\nEnvironment="SYSTEMD_SULOGIN_FORCE=1"\n' > "$sd/etc/systemd/system/rescue.service.d/force.conf"
printf '[Service]\nExecStart=-/bin/sh\n' > "$sd/usr/lib/systemd/system/emergency.service"
ln -s /dev/null "$sd/etc/systemd/system/emergency.service"
printf 'root:!:19000:0:99999:7:::\n' > "$sd/etc/shadow"
out=`single "$sd"`
printf '%s\n' "$out" | grep -q 'WARN.*sum003w.*rescue.service runs sulogin told to let root in' &&
  ok "SYSTEMD_SULOGIN_FORCE=1 with root locked: sum003w" || bad "SYSTEMD_SULOGIN_FORCE: $out"
printf '%s\n' "$out" | grep -q 'emergency.service' && bad "a masked emergency.service was judged" ||
  ok "a unit masked in /etc (linked to /dev/null) starts nothing: quiet"
printf 'root:$y$j9T$salt$hash:19000:0:99999:7:::\n' > "$sd/etc/shadow"
[ -z "`single "$sd"`" ] && ok "SYSTEMD_SULOGIN_FORCE=1 with root's password set: quiet" || bad "forced, root unlocked: `single "$sd"`"
# on this host, live, whatever its architecture
( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_single ) 2>&1 | grep -q '^# Checking for single user-mode password' &&
  ok "it runs on this host (`uname -m`)" || bad "check_single did not run on `uname -m`"

[ $fail -eq 0 ] && echo "PASS" || { echo "--- findings"; grep -h '"type":"finding"' "$json" "$json2" | cut -c1-220; }
exit $fail
