#!/bin/sh
#
# tests/offline_boot_check.sh - the boot checks on an offline root
#
# Two roots run with the boot and single-user checks on. The first has
# a group- and world-readable lilo.conf with no password and a
# group- and world-readable grub.cfg that does set one: every leg must
# be reported by the root's own paths. Its lilo.conf also keeps the
# single-user check silent, as on a live system. The second root has
# no boot loader configuration at all but an inittab without sulogin:
# the missing configuration and the missing sulogin line must both be
# reported. check_lilo needs root (the boot loader's configuration is
# root's): as a user it must be skipped as such, and as root its
# findings are checked too. CI runs this both ways.
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
grep '"type":"finding"' "$json" | grep -q 'sum001f' &&
  bad "the single-user check spoke though lilo.conf exists" ||
  ok "with lilo.conf present the single-user check stays silent"
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

[ $fail -eq 0 ] && echo "PASS" || { echo "--- findings"; grep -h '"type":"finding"' "$json" "$json2" | cut -c1-220; }
exit $fail
