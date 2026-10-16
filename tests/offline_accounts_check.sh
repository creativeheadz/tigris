#!/bin/sh
#
# tests/offline_accounts_check.sh - the account checks on an offline root
#
# Builds a root with accounts that are wrong in known ways and runs
# tigris --root on it with the account checks on: a second uid-0 account,
# an empty password, a duplicate uid, a disabled account with a shell, a
# .rhosts and a crontab (where Debian keeps crontabs), a world-writable
# home, password aging off, a securetty that lets root in remotely, and
# '.' in root's PATH. Each must be reported, by the root's paths and with
# owners named from the root's passwd, never this host's. root's .profile
# also tries to make Tigris write a file through a redirection
# (PATH=...>file): nothing may be written. check_passwd needs root (a live
# shadow file is root's): as a user it must be skipped as such, and as root
# its findings are checked too. CI runs this both ways.
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

# The root. milo has this test's uid, so the files the test makes are his
# by the root's passwd, whatever this host calls that uid.
R=$W/img
U=$uid; G=`id -g`
# as root, the root's files are given to an ordinary uid, so that owners
# mean what they mean as a user
[ "$uid" = 0 ] && { U=4242; G=4242; }
mkdir -p "$R/etc" "$R/bin" "$R/home/milo" "$R/home/wren" "$R/var/spool/cron/crontabs" "$R/root"
printf '#!/bin/sh\n' > "$R/bin/bash"; chmod 755 "$R/bin/bash"
cat > "$R/etc/passwd" <<EOF
root:x:0:0:root:/root:/bin/bash
toor:x:0:0:second root:/root:/bin/bash
milo:x:$U:$G:Milo:/home/milo:/bin/bash
eve:x:$((U + 1)):$G:Eve:/home/eve:/bin/sh
dup:x:$((U + 1)):$G:Duplicate:/home/dup:/usr/sbin/nologin
wren:x:$((U + 2)):$G:Wren:/home/wren:/bin/bash
EOF
cat > "$R/etc/shadow" <<'EOF'
root:$6$saltsalt$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEF:19000:0:99999:7:::
toor:$6$saltsalt$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEF:19000:0:99999:7:::
milo:*:19000:0:99999:7:::
eve::19000:0:99999:7:::
dup:*:19000:0:99999:7:::
wren:$6$saltsalt$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEF:19000:0::7:::
EOF
printf 'root:x:0:\ncrew:x:%s:\n' "$G" > "$R/etc/group"
printf '/bin/sh\n/bin/bash\n' > "$R/etc/shells"
printf 'console\nttyp0\n' > "$R/etc/securetty"
echo 'alice ALL' > "$R/home/milo/.rhosts"
echo '0 * * * * /bin/true' > "$R/var/spool/cron/crontabs/milo"
chmod 777 "$R/home/wren"
# root's PATH: '.' in it, and a line that would write a file if sourced
cat > "$R/.profile" <<EOF
PATH=.:/usr/bin:/bin
SNEAK=x>$W/written
export PATH
EOF

[ "$uid" = 0 ] && chown -R "$U:$G" "$R"

{
  sed -n 's/^\(Tigris_Check_[A-Z_]*\)=.*/\1=N/p' "$W/tigris.conf"
  echo 'Tigris_Deb_CheckMD5Sums=N'; echo 'Tigris_Deb_NoPackFiles=N'; echo 'Tigris_Deb_StatOverride=N'
  for c in PASSWD PASSWD_SHADOW ACCOUNTS ROOT_ACCESS ROOTDIR PATH SYSTEM; do echo "Tigris_Check_$c=Y"; done
} > "$W/profiles/accounts"
chmod 644 "$W/profiles/accounts"

( cd "$W" && sh ./tigris -q --profile accounts --root "$R" ) > "$W/out" 2>&1
json=`ls "$W"/log/*.jsonl 2>/dev/null | head -1`
[ -n "$json" ] || { echo "FAIL no report:"; cat "$W/out"; exit 1; }
has() { grep -q -- "$1" "$json"; }

if [ "$uid" = 0 ]; then
  has '"id":"pass017w".*Login ID toor has uid == 0' && ok "a second uid-0 account: pass017w" || bad "pass017w"
  has "\"id\":\"pass011f\".*Username .eve' has an empty password field" && ok "an empty password: pass011f" || bad "pass011f"
  has '"id":"pass002w".*UID '"$((U + 1))"' exists multiple times (2) in /etc/passwd' && ok "a duplicate uid, in the root's /etc/passwd: pass002w" || bad "pass002w"
  has '"id":"pass014w".*Login (milo) is disabled, but has a valid shell' && ok "a disabled account with a shell: pass014w" || bad "pass014w"
else
  has '{"type":"skip","check":"check_passwd","reason":"needs root"}' &&
    ok "as a user, check_passwd is skipped for root (its findings are checked as root)" || bad "check_passwd as a user"
fi
has '"id":"acc004w".*Login ID milo is disabled, but has a .rhosts file' &&
  ok "its .rhosts, owned by milo by the root's passwd: acc004w" || bad "acc004w"
has '"id":"acc005w".*Login ID milo is disabled, but has a .cron. file' &&
  ok "its crontab, in /var/spool/cron/crontabs: acc005w" || bad "acc005w"
has "\"id\":\"acc006w\".*Login ID wren's home directory (/home/wren) has .*world write access" && ok "a world-writable home: acc006w" || bad "acc006w"
has '"id":"pass019w".*Login ID wren does not have password aging enabled' && ok "aging off, read from the root's shadow: pass019w" || bad "pass019w"
has '"id":"root001w".*Remote root login allowed in /etc/securetty' && ok "securetty: root001w" || bad "root001w"
has "\"id\":\"path004w\".*PATH in root's .profile contains '.'" && ok "'.' in root's PATH, from the root's /.profile: path004w" || bad "path004w"
has '"id":"pass009f".*Login toor has a user id of 0' && ok "the format check runs in pwck's place: pass009f" || bad "pass009f"
[ -e "$W/written" ] && bad "a redirection in a .profile wrote a file" || ok "a redirection in a .profile is not sourced"
me=`id -un`
case " milo eve dup wren toor root crew " in
  *" $me "*) ok "(this host's user name is one of the root's; not checked)" ;;
  *) grep '"type":"finding"' "$json" | grep -q "\\b$me\\b" && bad "this host's user name, $me, appears in a finding" ||
       ok "no owner named by this host's passwd ($me)" ;;
esac
grep '"type":"finding"' "$json" | grep -q "$R" && bad "a finding names the root's directory on this host" ||
  ok "findings name the root's own paths, never where it is on this host"
sh "$W/tests/schema_check.sh" "$json" > "$W/schema.out" 2>&1 && ok "the report validates" ||
  { grep -q SKIP "$W/schema.out" && ok "(schema not checked: $(cat "$W/schema.out"))" || { bad "schema"; cat "$W/schema.out"; }; }

[ $fail -eq 0 ] && echo "PASS" || { echo "--- findings"; grep '"type":"finding"' "$json" | cut -c1-220; }
exit $fail
