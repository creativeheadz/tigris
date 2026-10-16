#!/bin/sh
#
# tests/offline_neverlogin_check.sh - the never-logged-in check on offline roots
#
# Three roots run with the check on. The first has a lastlog where
# root and one user did log in and the rest never did: the passworded
# never-users must be reported, the logged-in control and the locked
# and shell-less accounts must stay silent. The second root's lastlog
# is exactly the size both record layouts divide, so the believable
# timestamps must pick the layout. The third has an empty lastlog, as
# Ubuntu 24.04 leaves it (no SSH login is written there): nobody is on
# record, so nobody can be said never to have logged in, and only the
# account with no password is reported. check_neverlogin needs root (its
# hash test reads the shadow file): as a user it must be skipped as
# such, and as root its findings are checked too. CI runs this both
# ways.
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

# printf octal escapes and dd seeks are POSIX; the seeks past the end
# leave sparse holes, the way the real database looks.
putrec() {
  printf "$2" | dd of="$1" bs=1 seek="$3" conv=notrunc 2>/dev/null
}
padto() {
  printf '\000' | dd of="$1" bs=1 seek="$(($2 - 1))" conv=notrunc 2>/dev/null
}

R=$W/img
U=$uid; G=`id -g`
[ "$uid" = 0 ] && { U=4242; G=4242; }
mkdir -p "$R/etc" "$R/var/log"
cat > "$R/etc/passwd" <<EOF
root:x:0:0:root:/root:/bin/bash
alice:x:$U:$G:Alice:/home/alice:/bin/bash
bob:x:$((U + 1)):$G:Bob:/home/bob:/bin/bash
carol:x:$((U + 2)):$G:Carol:/home/carol:/bin/bash
svc:x:$((U + 3)):$G:Svc:/srv/svc:/usr/sbin/nologin
dave:x:$((U + 4)):$G:Dave:/home/dave:/bin/bash
EOF
cat > "$R/etc/shadow" <<'EOF'
root:$6$saltsalt$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefgh:19000:0:99999:7:::
alice:$6$saltsalt$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefgh:19000:0:99999:7:::
bob::19000:0:99999:7:::
carol:$6$saltsalt$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefgh:19000:0:99999:7:::
svc:$6$saltsalt$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefgh:19000:0:99999:7:::
dave:*:19000:0:99999:7:::
EOF
printf '/bin/sh\n/bin/bash\n' > "$R/etc/shells"
printf 'root:x:0:\ncrew:x:%s:\n' "$G" > "$R/etc/group"
putrec "$R/var/log/lastlog" '\001\002\003\004\005\006\007\010' 0
putrec "$R/var/log/lastlog" '\011\012\013\014\015\016\017\020' $(( (U + 2) * 296 ))
Mplus1=$((U + 5)); k=0; [ $((Mplus1 % 73)) -eq 0 ] && k=1
padto "$R/var/log/lastlog" $(( (Mplus1 + k) * 296 ))

T=$W/tied
mkdir -p "$T/etc" "$T/var/log"
cat > "$T/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
alice:x:10:10:Alice:/home/alice:/bin/bash
bob:x:11:10:Bob:/home/bob:/bin/bash
EOF
cat > "$T/etc/shadow" <<'EOF'
root:$6$saltsalt$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefgh:19000:0:99999:7:::
alice:$6$saltsalt$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefgh:19000:0:99999:7:::
bob::19000:0:99999:7:::
EOF
printf '/bin/sh\n/bin/bash\n' > "$T/etc/shells"
printf 'root:x:0:\ncrew:x:10:\n' > "$T/etc/group"
putrec "$T/var/log/lastlog" '\200\000\222\145\000\000\000\000' $((10 * 296))
padto "$T/var/log/lastlog" 21608

E=$W/empty
mkdir -p "$E/etc" "$E/var/log"
cat > "$E/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
alice:x:4444:4444:Alice:/home/alice:/bin/bash
carol:x:4446:4446:Carol:/home/carol:/bin/bash
EOF
cat > "$E/etc/shadow" <<'EOF'
root:$6$saltsalt$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefgh:19000:0:99999:7:::
alice:$6$saltsalt$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefgh:19000:0:99999:7:::
carol::19000:0:99999:7:::
EOF
: > "$E/var/log/lastlog"
printf '/bin/sh\n/bin/bash\n' > "$E/etc/shells"
printf 'root:x:0:\n' > "$E/etc/group"

[ "$uid" = 0 ] && { chown -R "$U:$G" "$R"; chown -R 0:10 "$T"; chown -R 0:0 "$E"; }

{
  sed -n 's/^\(Tigris_Check_[A-Z_]*\)=.*/\1=N/p' "$W/tigris.conf"
  echo 'Tigris_Deb_CheckMD5Sums=N'; echo 'Tigris_Deb_NoPackFiles=N'; echo 'Tigris_Deb_StatOverride=N'
  for c in NEVERLOG SYSTEM; do echo "Tigris_Check_$c=Y"; done
} > "$W/profiles/never"
chmod 644 "$W/profiles/never"

( cd "$W" && sh ./tigris -q --profile never --root "$R" ) > "$W/out" 2>&1
json=`ls "$W"/log/*.jsonl 2>/dev/null | head -1`
[ -n "$json" ] || { echo "FAIL no report:"; cat "$W/out"; exit 1; }
has() { grep -q -- "$1" "$json"; }

if [ "$uid" = 0 ]; then
  has '"id":"acc024f".*User alice has got a password and a valid shell (/bin/bash) but never logged in' &&
    ok "a passworded never-user: acc024f" || bad "acc024f alice"
  has '"id":"acc024f".*User bob has got NO password and a valid shell (/bin/bash)' &&
    ok "a passwordless never-user: acc024f" || bad "acc024f bob"
  grep '"type":"finding"' "$json" | grep -q 'User carol' &&
    bad "the logged-in control user reported something" ||
    ok "the logged-in control user stays silent"
  grep '"type":"finding"' "$json" | grep -q 'User svc' &&
    bad "the shell-less account reported something" ||
    ok "the shell-less account stays silent"
  grep '"type":"finding"' "$json" | grep -q 'User dave' &&
    bad "the locked account reported something" ||
    ok "the locked account stays silent"
  grep '"type":"finding"' "$json" | grep -q 'User root' &&
    bad "root, who logged in, reported something" ||
    ok "root, who logged in, stays silent"
  grep '"type":"finding"' "$json" | grep -q "$R" && bad "a finding names the root's directory on this host" ||
    ok "findings name the root's own paths, never where it is on this host"
  sh "$W/tests/schema_check.sh" "$json" > "$W/schema.out" 2>&1 && ok "the report validates" ||
    { grep -q SKIP "$W/schema.out" && ok "(schema not checked: $(cat "$W/schema.out"))" || { bad "schema"; cat "$W/schema.out"; }; }

  sleep 2
  ( cd "$W" && sh ./tigris -q --profile never --root "$T" ) > "$W/out2" 2>&1
  json2=`ls -t "$W"/log/*.jsonl 2>/dev/null | head -1`
  [ -n "$json2" ] && [ "$json2" != "$json" ] || { echo "FAIL no second report:"; cat "$W/out2"; exit 1; }
  grep -q '"id":"acc024f".*User bob has got NO password' "$json2" &&
    grep -q '"id":"acc024f".*User root has got a password' "$json2" &&
    ok "the tied layout resolves and the never-users report: acc024f" || bad "acc024f tied"
  grep '"type":"finding"' "$json2" | grep -q 'User alice' &&
    bad "the tied layout misread the logged-in user" ||
    ok "the tied layout reads the logged-in user rightly"
  grep '"type":"finding"' "$json2" | grep -q "$T" && bad "a finding names the second root's directory on this host" ||
    ok "the second report names the root's own paths too"
  sh "$W/tests/schema_check.sh" "$json2" > "$W/schema2.out" 2>&1 && ok "the second report validates" ||
    { grep -q SKIP "$W/schema2.out" && ok "(schema not checked: $(cat "$W/schema2.out"))" || { bad "schema2"; cat "$W/schema2.out"; }; }

  sleep 2
  ( cd "$W" && sh ./tigris -q --profile never --root "$E" ) > "$W/out3" 2>&1
  json3=`ls -t "$W"/log/*.jsonl 2>/dev/null | head -1`
  [ -n "$json3" ] && [ "$json3" != "$json2" ] || { echo "FAIL no third report:"; cat "$W/out3"; exit 1; }
  grep -q '"id":"acc024f".*User carol has got NO password' "$json3" &&
    ! grep -q '"id":"acc024f".*has got a password' "$json3" &&
    ok "with an empty lastlog only the passwordless account is reported" || bad "acc024f empty: `grep acc024f "$json3" | cut -c1-160`"
  grep '"type":"finding"' "$json3" | grep -q "$E" && bad "a finding names the third root's directory on this host" ||
    ok "the third report names the root's own paths too"
  sh "$W/tests/schema_check.sh" "$json3" > "$W/schema3.out" 2>&1 && ok "the third report validates" ||
    { grep -q SKIP "$W/schema3.out" && ok "(schema not checked: $(cat "$W/schema3.out"))" || { bad "schema3"; cat "$W/schema3.out"; }; }
else
  has '{"type":"skip","check":"check_neverlogin","reason":"needs root"}' &&
    ok "as a user, check_neverlogin is skipped for root (its findings are checked as root)" || bad "check_neverlogin as a user"
  sh "$W/tests/schema_check.sh" "$json" > "$W/schema.out" 2>&1 && ok "the report validates" ||
    { grep -q SKIP "$W/schema.out" && ok "(schema not checked: $(cat "$W/schema.out"))" || { bad "schema"; cat "$W/schema.out"; }; }
fi

[ $fail -eq 0 ] && echo "PASS" || { echo "--- findings"; grep -h '"type":"finding"' "$W"/log/*.jsonl | cut -c1-220; }
exit $fail
