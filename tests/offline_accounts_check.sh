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
sync:x:4:65534:sync:/bin:/bin/sync
EOF
cat > "$R/etc/shadow" <<'EOF'
root:$6$saltsalt$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEF:19000:0:99999:7:::
toor:$6$saltsalt$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEF:19000:0:99999:7:::
milo:*:19000:0:99999:7:::
eve::19000:0:99999:7:::
dup:*:19000:0:99999:7:::
wren:$6$saltsalt$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEF:19000:0::7:::
sync:*:19000:0:99999:7:::
EOF
printf 'root:x:0:\ncrew:x:%s:\n' "$G" > "$R/etc/group"
printf '/bin/sh\n/bin/bash\n' > "$R/etc/shells"
printf 'console\nttyp0\n' > "$R/etc/securetty"
echo 'alice ALL' > "$R/home/milo/.rhosts"
echo '0 * * * * /bin/true' > "$R/var/spool/cron/crontabs/milo"
chmod 777 "$R/home/wren"
# milo's home is his own and 750; wren's is milo's by uid and open to
# all. History files: milo's bash history a link to /dev/null (none
# kept, on purpose), wren's zsh history a link elsewhere and her sh
# history a directory, root's a plain file. sync is a system account
# with a shell and a shared home (/bin), which is not judged.
chmod 750 "$R/home/milo"
ln -s /dev/null "$R/home/milo/.bash_history"
ln -s /var/tmp/.h "$R/home/wren/.zsh_history"
mkdir "$R/home/wren/.sh_history"
: > "$R/root/.bash_history"
# login.defs as Debian and Ubuntu ship it, and PAM, as everywhere
mkdir -p "$R/etc/pam.d"
printf '# Password aging controls:\nPASS_MAX_DAYS\t99999\nPASS_MIN_DAYS\t0\nPASS_WARN_AGE\t7\n#PASS_MIN_LEN\nUID_MIN\t1000\n' > "$R/etc/login.defs"
printf 'auth required pam_unix.so\n' > "$R/etc/pam.d/login"
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
has "\"id\":\"acc026w\".*Login ID wren's home directory (/home/wren) is readable and searchable by everyone" &&
  ok "a 777 home is open to read and search too: acc026w" || bad "acc026w"
if [ "$uid" = 0 ]; then
  has "\"id\":\"acc027w\".*Login ID wren's home directory (/home/wren) is owned by milo (uid $U), not by wren (uid $((U + 2)))" &&
    ok "a home owned by another account, the owner named from the root's passwd: acc027w" || bad "acc027w"
else
  # an image a user unpacked is all that user's: owners say nothing
  grep '"type":"finding"' "$json" | grep -q 'acc027w' &&
    bad "acc027w as a user, where every file is the runner's" || ok "as a user, the runner's own files are not judged for ownership: no acc027w"
fi
grep '"type":"finding"' "$json" | grep -q "acc02[67]w.*Login ID milo" &&
  bad "milo's 750 home, his own, was reported" || ok "a 750 home the account owns: no acc026w, no acc027w"
grep '"type":"finding"' "$json" | grep -q "acc02[678]w.*Login ID sync" &&
  bad "the system account sync (uid 4, home /bin, a shell) was judged" || ok "a system account's shared home is not judged"
has "\"level\":\"INFO\",\"id\":\"acc028w\".*Login ID milo's .bash_history is a symbolic link to /dev/null" &&
  ok "a history file linked to /dev/null: acc028w, INFO" || bad "acc028w /dev/null"
has "\"level\":\"WARN\",\"id\":\"acc028w\".*Login ID wren's .zsh_history is a symbolic link to /var/tmp/.h, not a regular file" &&
  ok "a history file linked elsewhere: acc028w, WARN" || bad "acc028w link"
has "\"level\":\"WARN\",\"id\":\"acc028w\".*Login ID wren's .sh_history is not a regular file" &&
  ok "a history file that is a directory: acc028w, WARN" || bad "acc028w directory"
grep '"type":"finding"' "$json" | grep -q "acc028w.*Login ID root" &&
  bad "root's plain .bash_history was reported" || ok "a plain history file is nothing"
has '"id":"pass019w".*Login ID wren does not have password aging enabled' && ok "aging off, read from the root's shadow: pass019w" || bad "pass019w"
has '"id":"pass023i".*never expire: PASS_MAX_DAYS is 99999 in /etc/login.defs' &&
  ok "login.defs is judged with /etc/pam.d/login there; 99999 is INFO: pass023i" || bad "pass023i"
grep '"type":"finding"' "$json" | grep -q 'pass024w\|pass007w' &&
  bad "stock login.defs (99999, 0, 7; no PASS_MIN_LEN under PAM) gave a WARN" ||
  ok "stock login.defs gives no WARN: PASS_MIN_DAYS 0 is not judged without expiry, PASS_MIN_LEN not asked for under PAM"
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

# Password hashes, check_passwd called directly (so it runs as a user too)
# on a root of its own: DES, md5crypt, a legacy format and one Tigris does
# not know must each be reported; yescrypt, bcrypt, sha256crypt and the
# locked ones (! or * in front, the x placeholder) must not.
H=$W/hashes; mkdir -p "$H/etc"
n=2000
: > "$H/etc/passwd"; : > "$H/etc/shadow"
for a in 'des abJnggxhB/yWI' 'md5u $1$saltsalt$abcdefghijklmnopqrstuv' 'sha1u $sha1$40000$saltsalt$abcdefghijklmnopqrstuvwxyz12' \
         'odd $9$abc$defghijklmnop' 'yes $y$j9T$saltsaltsaltsaltsalt$abcdefghijklmnopqrstuvwxyzABCDEFGHIJK' \
         'bcr $2b$12$abcdefghijklmnopqrstuuABCDEFGHIJKLMNOPQRSTUVWXYZ01234' 's256 $5$saltsalt$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ' \
         'lck !$6$saltsalt$abcdefghijklmnop' 'star *' 'xx x'
do
  set -f; set -- $a; set +f; n=$((n + 1))   # (no glob: one hash is *)
  printf '%s:x:%s:%s::/nonexistent:/usr/sbin/nologin\n' "$1" "$n" "$n" >> "$H/etc/passwd"
  printf '%s:%s:19000:1:90:7:::\n' "$1" "$2" >> "$H/etc/shadow"
done
( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$H" sh ./scripts/check_passwd ) 2>&1 |
  awk '/^--[A-Z]+-- \[/ { if (s != "") print s; s = $0; next } /^ / && s != "" { sub(/^ +/, " "); s = s $0; next } END { if (s != "") print s }' > "$W/hash.out"
hash013() { grep 'pass013w' "$W/hash.out" | grep -q "\`$1'"; }
for u in des md5u sha1u
do
  hash013 "$u" && ok "a weak hash ($u) is reported: pass013w" || bad "pass013w for $u"
done
grep 'pass013w' "$W/hash.out" | grep -q "\`odd' has a password hash in a format Tigris does not recognise" &&
  ok "a hash in a format Tigris does not know is reported, not taken for locked" || bad "pass013w for an unknown format"
for u in yes bcr s256 lck star xx
do
  hash013 "$u" && bad "pass013w for $u" || ok "no pass013w for $u"
done

# login.defs' ageing, check_passwdspec alone on roots of its own
defs() {  # defs DIR MAX MIN WARN [pam]: a root whose login.defs sets them
  mkdir -p "$W/$1/etc"
  printf 'PASS_MAX_DAYS %s\nPASS_MIN_DAYS %s\nPASS_WARN_AGE %s\n' "$2" "$3" "$4" > "$W/$1/etc/login.defs"
  [ "$5" = pam ] && { mkdir -p "$W/$1/etc/pam.d"; : > "$W/$1/etc/pam.d/login"; }
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$W/$1" sh ./systems/Linux/2/check_passwdspec ) 2>&1 |
    awk '/^--[A-Z]+-- \[/ { if (s != "") print s; s = $0; next } /^ / && s != "" { sub(/^ +/, " "); s = s $0; next } END { if (s != "") print s }' > "$W/$1.out"
}
defs d1 90 0 7 pam
grep -q 'pass024w.*PASS_MIN_DAYS is 0 in /etc/login.defs while passwords expire after 90 days' "$W/d1.out" &&
  ok "expiry on with PASS_MIN_DAYS 0: pass024w" || bad "PASS_MIN_DAYS 0 with expiry: `cat "$W/d1.out"`"
defs d2 30 60 7 pam
grep -q 'pass024w.*PASS_MIN_DAYS (60, in /etc/login.defs) is more than PASS_MAX_DAYS (30)' "$W/d2.out" &&
  ok "a minimum above the maximum: pass024w" || bad "min above max: `cat "$W/d2.out"`"
defs d3 90 1 0 pam
grep -q 'pass024w.*PASS_WARN_AGE is 0' "$W/d3.out" && ok "expiry on with no warning: pass024w" || bad "no warning: `cat "$W/d3.out"`"
defs d4 90 1 7 pam
[ ! -s "$W/d4.out" ] && ok "90, 1, 7 under PAM: quiet" || bad "a sound login.defs: `cat "$W/d4.out"`"
defs d5 90 1 7
grep -q 'pass007w.*PASS_MIN_LEN missing from /etc/login.defs' "$W/d5.out" &&
  ok "without PAM, PASS_MIN_LEN is asked for: pass007w" || bad "PASS_MIN_LEN without PAM: `cat "$W/d5.out"`"
# openSUSE: the vendor's file in /usr/etc, a drop-in in /etc/login.defs.d
O=$W/suse; mkdir -p "$O/etc/login.defs.d" "$O/usr/etc" "$O/etc/pam.d"; : > "$O/etc/pam.d/login"
printf 'PASS_MAX_DAYS 99999\nPASS_MIN_DAYS 0\nPASS_WARN_AGE 7\n' > "$O/usr/etc/login.defs"
printf 'PASS_MAX_DAYS 60\n' > "$O/etc/login.defs.d/50-policy.defs"
( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$O" sh ./systems/Linux/2/check_passwdspec ) > "$W/suse.out" 2>&1
tr -s ' \n' '  ' < "$W/suse.out" | grep -q 'pass024w\] PASS_MIN_DAYS is 0 in /usr/etc/login.defs while passwords expire after 60 days' &&
  ok "/usr/etc/login.defs with a login.defs.d drop-in on top: pass024w" || bad "vendor login.defs and drop-in: `cat "$W/suse.out"`"

# Expired yet usable accounts (pass025w), check_passwdspec on a root of
# its own. Day 19000 is January 2022; today is this host's.
X=$W/expired; mkdir -p "$X/etc"
now=$(( $(date +%s) / 86400 ))
cat > "$X/etc/passwd" <<EOF
root:x:0:0:root:/root:/bin/bash
old:x:2001:2001:password expired, no inactivity:/home/old:/bin/sh
gone:x:2002:2002:account expired:/home/gone:/bin/bash
idle:x:2003:2003:expired and past its inactivity period:/home/idle:/bin/sh
svc:x:2004:2004:expired, cannot log in:/home/svc:/usr/sbin/nologin
lock:x:2005:2005:expired, locked:/home/lock:/bin/sh
fresh:x:2006:2006:changed ten days ago:/home/fresh:/bin/sh
reset:x:2007:2007:must change at next login:/home/reset:/bin/sh
soon:x:2008:2008:expires tomorrow:/home/soon:/bin/sh
EOF
H='$6$saltsalt$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEF'
cat > "$X/etc/shadow" <<EOF
root:$H:$((now - 10)):0:99999:7:::
old:$H:19000:0:90:7:::
gone:$H:$((now - 10)):0:99999:7::19100:
idle:$H:19000:0:90:7:30::
svc:$H:19000:0:90:7:::
lock:!$H:19000:0:90:7:::
fresh:$H:$((now - 10)):0:90:7:::
reset:$H:0:0:90:7:::
soon:$H:$((now - 89)):0:90:7:::
EOF
( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$X" sh ./systems/Linux/2/check_passwdspec ) 2>&1 |
  awk '/^--[A-Z]+-- \[/ { if (s != "") print s; s = $0; next } /^ / && s != "" { sub(/^ +/, " "); s = s $0; next } END { if (s != "") print s }' > "$W/expired.out"
grep -q "pass025w\] Login ID old's password expired $((now - 19090)) days ago (last change plus maximum age in /etc/shadow) and the account is not locked and keeps a login shell" "$W/expired.out" &&
  ok "a password past its maximum age, unlocked, with a shell: pass025w, saying how long ago" || bad "pass025w password: `cat "$W/expired.out"`"
grep -q "pass025w\] Login ID gone's account expired $((now - 19100)) days ago (the expiry date in /etc/shadow) but its password is not locked and it keeps a login shell" "$W/expired.out" &&
  ok "an account past its expiry date, unlocked, with a shell: pass025w" || bad "pass025w account: `cat "$W/expired.out"`"
for u in idle svc lock fresh reset soon root
do
  grep -q "pass025w\] Login ID $u's" "$W/expired.out" && bad "pass025w for $u" || ok "no pass025w for $u (`awk -F: -v u="$u" '$1 == u { print $5 }' "$X/etc/passwd"`)"
done

[ $fail -eq 0 ] && echo "PASS" || { echo "--- findings"; grep '"type":"finding"' "$json" | cut -c1-220; cat "$W/hash.out"; }
exit $fail
