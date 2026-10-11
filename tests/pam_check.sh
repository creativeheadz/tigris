#!/bin/sh
#
# tests/pam_check.sh - check_pam against PAM stacks of its own
#
# Trees under Tiger_Sysctl_Root with the stacks distributions ship:
# Debian's common-auth and common-password (pam_unix only), Fedora's
# system-auth from authselect (pam_pwquality, controls in brackets),
# Arch's system-auth (pam_faillock), openSUSE's defaults in /usr/lib/pam.d
# with one overridden in /etc/pam.d.
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

go() {
  cp "$W/tigerrc.base" "$W/tigerrc"
  echo "Tiger_Sysctl_Root='$W/$1'" >> "$W/tigerrc"
  ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_pam ) 2>&1 |
    awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
    tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out"
}
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -c -- "$1" "$W/out"; }

d="$W/debian/etc/pam.d"; mkdir -p "$d"
cat > "$d/common-auth" <<'EOF'
# here are the per-package modules (the "Primary" block)
auth	[success=1 default=ignore]	pam_unix.so nullok
auth	requisite			pam_deny.so
auth	required			pam_permit.so
EOF
cat > "$d/common-password" <<'EOF'
password	[success=1 default=ignore]	pam_unix.so obscure yescrypt
# password requisite pam_pwquality.so retry=3
password	requisite			pam_deny.so
EOF
go debian
has '--WARN-- [pam001w] Passwords are not checked for quality' && has '--WARN-- [pam003w] Accounts are not locked' &&
  ok "Debian's defaults (pwquality commented out): pam001w and pam003w" || { bad "debian"; cat "$W/out"; }

f="$W/fedora/etc/pam.d"; mkdir -p "$f" "$W/fedora/etc/security"
cat > "$f/system-auth" <<'EOF'
auth        required                                     pam_env.so
auth        sufficient                                   pam_unix.so nullok
auth        required                                     pam_deny.so
password    requisite                                    pam_pwquality.so local_users_only
password    sufficient                                   pam_unix.so yescrypt shadow nullok use_authtok
password    required                                     pam_deny.so
EOF
go fedora
[ "`count pam001w`" = 0 ] && [ "`count pam002w`" = 0 ] && has '[pam003w]' &&
  ok "Fedora's authselect stack: quality (default minlen 8), no lockout" || { bad "fedora"; cat "$W/out"; }
echo 'minlen = 6' > "$W/fedora/etc/security/pwquality.conf"
go fedora
has '--WARN-- [pam002w] New passwords may be as short as 6 characters.' && ok "pwquality.conf minlen = 6: pam002w" || { bad "minlen conf"; cat "$W/out"; }
mkdir -p "$W/fedora/etc/security/pwquality.conf.d"; echo 'minlen = 14' > "$W/fedora/etc/security/pwquality.conf.d/50-site.conf"
go fedora
[ "`count pam002w`" = 0 ] && ok "a pwquality.conf.d file overrides it" || { bad "minlen conf.d"; cat "$W/out"; }
sed -i 's/pam_pwquality.so local_users_only/pam_pwquality.so local_users_only minlen=5/' "$f/system-auth"
go fedora
has 'as short as 5 characters' && ok "minlen= on the module line wins over the files" || { bad "minlen arg"; cat "$W/out"; }

a="$W/arch/etc/pam.d"; mkdir -p "$a"
cat > "$a/system-auth" <<'EOF'
#%PAM-1.0
auth       required                    pam_faillock.so      preauth
-auth      [success=2 default=ignore]  pam_systemd_home.so
auth       [success=1 default=bad]     pam_unix.so          try_first_pass nullok
auth       [default=die]               pam_faillock.so      authfail
-password  [success=1 default=ignore]  pam_systemd_home.so
password   required                    pam_unix.so          try_first_pass nullok shadow
EOF
go arch
has '[pam001w]' && [ "`count pam003w`" = 0 ] && ok "Arch's system-auth: faillock, no quality check" || { bad "arch"; cat "$W/out"; }
echo '-password  requisite  pam_pwquality.so retry=3' >> "$a/system-auth"
go arch
[ "`count .`" = 0 ] && ok "a quality module on a -password line counts" || { bad "dash type"; cat "$W/out"; }

s="$W/suse"; mkdir -p "$s/usr/lib/pam.d" "$s/etc/pam.d"
printf 'auth required pam_faillock.so preauth\nauth required pam_unix.so\n' > "$s/usr/lib/pam.d/common-auth"
printf 'password requisite pam_pwquality.so\n' > "$s/usr/lib/pam.d/common-password"
printf 'auth required pam_unix.so\n' > "$s/etc/pam.d/common-auth"
go suse
has '[pam003w]' && [ "`count pam001w`" = 0 ] &&
  ok "openSUSE: /usr/lib/pam.d read, a file of the same name in /etc/pam.d overrides it" || { bad "suse"; cat "$W/out"; }

mkdir -p "$W/none"; go none
[ "`count .`" = 0 ] && ok "no PAM: nothing said" || { bad "none"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
