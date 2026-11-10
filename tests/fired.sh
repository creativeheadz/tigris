#!/bin/sh
#
# tests/fired.sh - every finding id is reported by some suite, or is on
# the list of those that are not yet
#
# A check can pass its suite and still never report: in October 2026 the
# single-user check, the AIDE database check and the GRUB 2 check were
# found to have been silent on every current system. An id nobody has
# seen reported proves nothing. So message() writes each id it is handed
# to Tigris_Fired_Log, every suite is run with that set, once as this
# user and once as root in a debian:stable container (some findings are
# only looked for as root, some only as a user), and the ids seen are
# held against meta/:
#
# - an id no suite reported must be in tests/unfired.list. A new finding
#   id therefore arrives with a fixture that makes it report.
# - an id on the list that a suite did report must come off it, so the
#   list only shrinks.
#
# The list gives each id a reason:
#   none  no fixture reports it yet. This is the debt.
#   pkg   reported in tests/deb_checks.sh or tests/pkg_checks.sh, which
#         change the system they run on and have containers of their own.
#   raw   an --ERROR-- or --CONFIG-- line the start-up writes with echo,
#         before message() exists. A suite must name the id.
#
#   sh tests/fired.sh              run the suites, then judge
#   Tigris_Fired_Log=FILE sh tests/fired.sh
#                                  judge a log some other run wrote
#
# Not a *_check.sh: tests/all.sh must not run it (it runs all.sh), and
# it takes as long as two of those.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022
LC_ALL=C; export LC_ALL
W=`mktemp -d`
trap 'rm -rf "$W"' 0
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
LIST=$TIGER/tests/unfired.list

if [ -n "$Tigris_Fired_Log" ] && [ -s "$Tigris_Fired_Log" ]; then
  cp "$Tigris_Fired_Log" "$W/log"
else
  [ "`id -u`" != 0 ] || { echo "SKIP: run this as a user, the root half runs in a container"; exit 0; }
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 ||
    { echo "SKIP: docker is needed for the root half"; exit 0; }
  : > "$W/log"
  Tigris_Fired_Log=$W/log sh "$TIGER/tests/all.sh" > "$W/user.out" 2>&1
  mkdir "$W/out"
  docker run --rm -v "$TIGER:/tiger:ro" -v "$W/out:/out" -e Tigris_Fired_Log=/out/log debian:stable sh -c '
    apt-get update -qq >/dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq binutils file procps diffutils bsdextrautils sudo python3-jsonschema >/dev/null 2>&1
    sh /tiger/tests/all.sh; chmod 644 /out/log' > "$W/root.out" 2>&1
  [ -s "$W/out/log" ] || { echo "FAIL the container run reported nothing:"; tail -5 "$W/root.out"; exit 1; }
  cat "$W/out/log" >> "$W/log"
  # a suite that failed reported less than it should: say so, the
  # verdict below is then about the failure, not about the list
  grep -h '^FAIL ' "$W/user.out" "$W/root.out" | sort -u | sed 's/^/note: /'
fi

ls "$TIGER/meta" | sort > "$W/ids"
sort -u "$W/log" > "$W/fired"
comm -23 "$W/ids" "$W/fired" > "$W/unfired"
sed -e 's/#.*//' -e '/^[ 	]*$/d' "$LIST" > "$W/list"

# the list itself: an id that exists, a known reason, once, in order
awk '{ print $1 }' "$W/list" > "$W/listed"
x=`awk 'NF != 2 || $2 !~ /^(none|pkg|raw)$/' "$W/list"`
[ -z "$x" ] && ok "every line of the list is an id and a reason" || bad "not an id and one of none, pkg, raw: $x"
sort -c "$W/listed" 2>/dev/null && [ -z "`uniq -d "$W/listed"`" ] &&
  ok "the list is sorted, each id once" || bad "tests/unfired.list is not sorted, or names an id twice"
x=`comm -13 "$W/ids" "$W/listed" | tr '\n' ' '`
[ -z "$x" ] && ok "every listed id has its meta file" || bad "listed, but no such finding: $x"

x=`comm -23 "$W/unfired" "$W/listed" | tr '\n' ' '`
[ -z "$x" ] && ok "every finding id was reported by a suite, or is listed" ||
  bad "no suite reports these, and tests/unfired.list does not name them: $x"
x=`comm -12 "$W/fired" "$W/listed" | tr '\n' ' '`
[ -z "$x" ] && ok "nothing on the list was reported" ||
  bad "reported by a suite now, take them off tests/unfired.list: $x"

# raw: written with echo, so only a suite naming the id vouches for it
for id in `awk '$2 == "raw" { print $1 }' "$W/list"`; do
  grep -l -- "$id" "$TIGER"/tests/*.sh >/dev/null 2>&1 || { bad "$id is listed as raw, and no suite names it"; }
done
[ $fail -eq 0 ] && ok "every raw id is named by a suite"

n=`wc -l < "$W/ids"`; f=`comm -12 "$W/ids" "$W/fired" | wc -l`
echo "$f of $n finding ids reported; listed: `awk '$2 == "none"' "$W/list" | wc -l` none, `awk '$2 == "pkg"' "$W/list" | wc -l` pkg, `awk '$2 == "raw"' "$W/list" | wc -l` raw"
[ $fail -eq 0 ] && echo PASS || echo FAIL
exit $fail
