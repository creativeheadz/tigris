#!/bin/sh
#
# tests/software_check.sh - check_software on offline roots and a stub brew
#
# Five legs: loose (a world-writable app, a group-writable
# CoreServices file, a world-writable Cellar entry, automatic
# updates off); tight (755 throughout, group root, updates on);
# stock-group (a 775 app owned by group root stays silent, the
# same branch that exempts wheel and admin); an empty root; and a
# live leg with a stub brew whose Cellar entry is writable. The
# admin and wheel names cannot be fabricated on Linux, so the
# branch is exercised through group root instead. Runs as a user
# and as root; the fixtures read the same for both.
#
TIGER=${TIGER:-`cd "\`dirname \"$0\"\`/.." && pwd`}
W=`mktemp -d`
trap 'rm -rf "$W"' 0
umask 022
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run() {  # run ROOT OUTFILE: check_software with ROOT as the audited system
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/MacOSX/default/check_software ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }
empty() { [ ! -s "$1" ]; }

B=$W/bad
mkdir -p "$B/etc" "$B/Applications/Evil.app/Contents/MacOS" \
         "$B/System/Library/CoreServices" \
         "$B/opt/homebrew/Cellar/wget/1.21.4/bin" \
         "$B/Library/Preferences"
touch "$B/Applications/Evil.app/Contents/MacOS/evil" \
      "$B/System/Library/CoreServices/bootstrapper" \
      "$B/opt/homebrew/Cellar/wget/1.21.4/bin/wget"
chmod 777 "$B/Applications/Evil.app"
chmod 664 "$B/System/Library/CoreServices/bootstrapper"
chgrp "`awk -F: '$1 != "root" { print $1; exit }' /etc/group`" "$B/System/Library/CoreServices/bootstrapper" 2>/dev/null || true
chmod 777 "$B/opt/homebrew/Cellar/wget/1.21.4/bin/wget"
cat > "$B/Library/Preferences/com.apple.SoftwareUpdate.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>AutomaticCheckEnabled</key>
	<false/>
</dict>
</plist>
EOF
run "$B" "$W/out"
has '--WARN-- [swd001w]' "$W/out" &&
has 'Evil.app' "$W/out" &&
has 'Cellar' "$W/out" &&
has '--WARN-- [swd002w]' "$W/out" &&
  ok "writable app, CoreServices, Cellar, updates off: both" || { bad "bad"; cat "$W/out"; }

T=$W/tight
mkdir -p "$T/etc" "$T/Applications/Good.app/Contents/MacOS" \
         "$T/System/Library/CoreServices" \
         "$T/opt/homebrew/Cellar/wget/1.21.4/bin" \
         "$T/Library/Preferences"
touch "$T/Applications/Good.app" 2>/dev/null || true
chmod 755 "$T/Applications/Good.app" "$T/System/Library/CoreServices" \
          "$T/opt/homebrew/Cellar/wget/1.21.4/bin"
cat > "$T/Library/Preferences/com.apple.SoftwareUpdate.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>AutomaticCheckEnabled</key>
	<true/>
</dict>
</plist>
EOF
run "$T" "$W/out"
empty "$W/out" &&
  ok "755 throughout, updates on: silent" || { bad "tight noisy"; cat "$W/out"; }

S=$W/stock
mkdir -p "$S/etc" "$S/Applications/Stock.app"
chmod 775 "$S/Applications/Stock.app"
run "$S" "$W/out"
if chgrp root "$S/Applications/Stock.app" 2>/dev/null; then
  # root can put the stock group on: privileged groups stay silent
  chmod 775 "$S/Applications/Stock.app"
  run "$S" "$W/out"
  empty "$W/out" &&
    ok "775 group-root app: silent" || { bad "stock noisy"; cat "$W/out"; }
else
  # as a user the group stays an ordinary one: the same mode reports
  has '--WARN-- [swd001w]' "$W/out" &&
    ok "775 ordinary-group app: reports" || { bad "stock silent"; cat "$W/out"; }
fi

E=$W/emptyroot; mkdir -p "$E/etc"
run "$E" "$W/out"
empty "$W/out" &&
  ok "empty root: silent" || { bad "empty noisy"; cat "$W/out"; }

mkdir -p "$W/brewhome/Cellar/nope/1.0/bin"
touch "$W/brewhome/Cellar/nope/1.0/bin/nope"
chmod 777 "$W/brewhome/Cellar/nope/1.0/bin/nope"
cat > "$W/fakebrew" <<EOF
#!/bin/sh
echo "$W/brewhome"
EOF
chmod 755 "$W/fakebrew"
echo "Tigris_Brew_Cmd='$W/fakebrew'" >> "$W/tigris.conf"
( cd "$W" && TIGERHOMEDIR=$W sh ./systems/MacOSX/default/check_software ) 2>&1 |
awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out" || true
sed -i '$d' "$W/tigris.conf"
has '--WARN-- [swd001w]' "$W/out" &&
has 'Cellar' "$W/out" &&
  ok "stub brew Cellar: swd001w" || { bad "brew"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
