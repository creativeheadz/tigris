#!/bin/sh
#
# tests/hostile_root_check.sh - an offline root cannot make Tigris run code
#
# tigris --root reads images that may be hostile, and runs as root to do
# it. Whatever it reads from one is data, and none of it may be run. This
# root plants a command in each place a check once parsed as shell code:
# an account's name, password hash, shell and home directory, a line of
# /etc/shells, a
# group name, a file name in /dev, /etc/hostname (matched against
# bootparams), a value in sshd_config, a program name in root's PATH
# (built into an awk program), a top-level directory's name (built into
# a sed script). Each command is a bare redirection
# that would create a file named pwned.* in the directory Tigris runs
# from, so a Tigris that fails this test is not harmed by it. None may
# appear, and the checks must still report what they report on a fair
# root. CI runs this as a user and as root.
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
# as root, the root's files are given to an ordinary uid, so that owners
# mean what they mean as a user
[ "$uid" = 0 ] && { U=4242; G=4242; }
mkdir -p "$R/etc/ssh" "$R/bin" "$R/dev" "$R/root" "$R/usr/local/bin" \
  "$R/home/n" "$R/home/fair" "$R/h\`>pwned.home\`/x" "$R/export/root"
printf '#!/bin/sh\n' > "$R/bin/bash"; chmod 755 "$R/bin/bash"
printf '#!/bin/sh\n' > "$R/bin/sh"; chmod 755 "$R/bin/sh"
# a shell whose path holds the command; it exists, as check_accounts only
# looks at accounts whose shell does
printf '#!/bin/sh\n' > "$R/bin/sh\`>pwned.shell\`"; chmod 755 "$R/bin/sh\`>pwned.shell\`"

# n owns the files this test makes, so the image's passwd names their
# owner with the command; fair is an ordinary account
cat > "$R/etc/passwd" <<EOF
root:x:0:0:root:/root:/bin/bash
n\`>pwned.name\`:x:$U:$G::/home/n:/bin/bash
fair:x:$((U + 1)):$G:Fair:/home/fair:/bin/bash
sh1:x:$((U + 2)):$G::/home/fair:/bin/sh\`>pwned.shell\`
hh:x:$((U + 3)):$G::/h\`>pwned.home\`/x:/bin/bash
ct:x:$((U + 4)):$G::/home/c%g;eid>pwned.tilde;#:/bin/bash
EOF
# a home directory whose name ends the sed s command that expands ~ in
# a C shell start-up file, and adds GNU sed's e
mkdir -p "$R/home/c%g;eid>pwned.tilde;#"
printf 'set path = ( ~/bin /bin )\n' > "$R/home/c%g;eid>pwned.tilde;#/.cshrc"
cat > "$R/etc/shadow" <<EOF
root:*:19000:0:99999:7:::
n\`>pwned.name\`:\`>pwned.hash\`:19000:0:99999:7:::
fair:\$6\$saltsalt\$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEF:19000:0:99999:7:::
sh1:*:19000:0:99999:7:::
hh:*:19000:0:99999:7:::
ct:*:19000:0:99999:7:::
EOF
printf 'root:x:0:\ng`>pwned.group`:x:%s:\n' "$G" > "$R/etc/group"
printf '/bin/x`>pwned.shells`\n/bin/sh\n/bin/bash\n' > "$R/etc/shells"

# root's PATH holds a group-writable program; its group is named by the
# image's /etc/group
printf 'PATH=/usr/local/bin:/bin\nexport PATH\n' > "$R/.profile"
# and in root's home, where the every-account PATH check reads it
cp "$R/.profile" "$R/root/.profile"
printf '#!/bin/sh\n' > "$R/usr/local/bin/tool"; chmod 775 "$R/usr/local/bin/tool"
# a program in root's PATH whose name closes the string an awk program
# was built around (check_embed) and calls system()
evil='x",system("id>pwned.awk"),"'
printf '#!/bin/sh\n/bin/true\n' > "$R/usr/local/bin/$evil"; chmod 755 "$R/usr/local/bin/$evil"
# a top-level directory, where lost+found is looked for offline, whose
# name ends a sed s command and adds GNU sed's e, which runs a command
mkdir -p "$R/a%%;eid>pwned.sed;#/lost+found"
: > "$R/a%%;eid>pwned.sed;#/lost+found/stray"

# a regular file in /dev whose name holds the command
: > "$R/dev/a\`>pwned.dev\`"

# the bootparams servers are matched against the image's hostname
printf 'img`>pwned.host`\n' > "$R/etc/hostname"
printf 'diskless1 root=img:/export/root\n' > "$R/etc/bootparams"
printf '/export/root (root=diskless1)\n' > "$R/etc/exports"

printf 'PasswordAuthentication `>pwned.ssh`\nPermitRootLogin yes\n' > "$R/etc/ssh/sshd_config"

[ "$uid" = 0 ] && chown -R "$U:$G" "$R"

# Every check on, so that each one that reads what was planted is put to
# it (only five were, and check_passwd's own eval went unseen until the
# next day); the package database checks have no database here to read
{
  sed -n 's/^\(Tigris_Check_[A-Z_]*\)=.*/\1=Y/p' "$W/tigris.conf"
  echo 'Tigris_Deb_CheckMD5Sums=N'; echo 'Tigris_Deb_NoPackFiles=N'; echo 'Tigris_Deb_StatOverride=N'
} > "$W/profiles/hostile"
# an odd name (fsys005a, listed through lsline) holding a backslash-n,
# in both spellings: read without -r folded the two backslashes into
# one, and awk -v then read the one as a newline, so the name was a
# finding line of its own in the report, until October 2026
: > "$R/etc/..zz\\\\n--ALERT-- [fsys005a] FORGED"
: > "$R/etc/..zz\\n--ALERT-- [fsys005a] FORGED"
chmod 644 "$W/profiles/hostile"

( cd "$W" && sh ./tigris -q --profile hostile --root "$R" ) > "$W/out" 2>&1
json=`ls "$W"/log/*.jsonl 2>/dev/null | head -1`
text=`ls "$W"/log/security.report.* 2>/dev/null | grep -v '\.jsonl$' | head -1`
# the odd names with a backslash-n: reported, and never as a line of their
# own (the offline scan needs GNU find; without it there is nothing to see)
if find / -maxdepth 0 -printf '' >/dev/null 2>&1; then
  grep -q '"id":"fsys005a"' "$json" && ok "the odd names in /etc are reported: fsys005a" || bad "no fsys005a for the odd names"
  [ "`grep -c '^--ALERT-- \[fsys005a\] FORGED' "$text"`" = 0 ] &&
    ok "a backslash-n in a name forges no finding line in the text report" || { bad "a forged finding line"; grep -n 'FORGED' "$text"; }
fi
[ -n "$json" ] || { echo "FAIL no report:"; cat "$W/out"; exit 1; }
has() { grep -q -- "$1" "$json"; }

# nothing planted ran, wherever it would have landed in the copy
for v in name hash shell home shells group dev host ssh awk sed tilde
do
  found=`find "$W" -name "pwned.$v" 2>/dev/null`
  [ -z "$found" ] && ok "nothing run from the image ($v)" || bad "a command planted in the image ran ($v): $found"
done

# and the checks still did their work on it
has '"id":"acc019w".*Login ID fair may be missing a shell initialization file /home/fair/.bashrc' &&
  ok "a shell /etc/shells lists is still recognised: acc019w" || bad "acc019w"
has '"id":"acc023w"' &&
  ok "a home's parent with a non-administrative owner: acc023w" || bad "acc023w"
has '"id":"path001w".*/usr/local/bin/tool in root' &&
  ok "a group-writable program in root's PATH: path001w" || bad "path001w"
has '"id":"dev003w".*is a regular file in a device directory' &&
  ok "a regular file in /dev: dev003w" || bad "dev003w"
grep -E -q '"id":"nfs01[12]w".*/export/root' "$json" &&
  ok "the export with root access is still reported" || bad "nfs011w/nfs012w"
sh "$W/tests/schema_check.sh" "$json" > "$W/schema.out" 2>&1 && ok "the report validates" ||
  { grep -q SKIP "$W/schema.out" && ok "(schema not checked: $(cat "$W/schema.out"))" || { bad "schema"; cat "$W/schema.out"; }; }

# A directory of the image that resolves to nothing (a symlink loop) has
# no entries. Listing it, or expanding a wildcard under it, must not list
# this host's / in its place, under the image's name.
ln -s loop2 "$R/etc/loop1"; ln -s loop1 "$R/etc/loop2"
listed=`cd "$W" && R="$R" sh -c '
  . ./config -q >/dev/null 2>&1; . ./initdefs >/dev/null 2>&1
  TIGRIS_ROOT=$R; TIGRIS_LINKS=$WORKDIR/links.loop
  sh ./util/rootpath "$TIGRIS_ROOT" "$TIGRIS_LINKS" < /dev/null 2>/dev/null
  export TIGRIS_ROOT TIGRIS_LINKS
  rootls /etc/loop1; rootglob "/etc/loop1/*"' 2>/dev/null`
[ -z "$listed" ] && ok "a symlink loop in the image lists nothing, not this host's /" ||
  bad "a symlink loop in the image listed: `echo $listed | cut -c1-120`"

[ $fail -eq 0 ] && echo "PASS" || { echo "--- findings"; grep '"type":"finding"' "$json" | cut -c1-220; echo "--- output"; cat "$W/out"; }
exit $fail
