#!/bin/sh
#
# tests/export_check.sh - tigris-export: a report as SARIF 2.1.0 and as CSV
#
# A synthetic JSON Lines report with a finding at every level, an ERROR
# and a CONFIG record, a skipped check, two accepted findings, a detail,
# an id with no metadata, and strings chosen to break a converter: quotes,
# commas, backslashes, control characters, UTF-8 and a lone high byte as
# the report escapes them, and messages that open with =, +, -, @ and a
# tab. Then a second report as no Tigris would write it (a bad escape, raw
# control and high bytes, half a surrogate pair, a record cut short, an id
# that is a path): what comes out must be valid whatever went in.
#
# The SARIF is parsed with python3 when there is one (that leg says so
# when there is none, and the rest still runs), and validated against the
# official SARIF 2.1.0 schema when SARIF_SCHEMA names a copy of it and
# the python jsonschema module is installed: the tests fetch nothing. The
# CSV is read back by an RFC 4180 reader in awk, and by python's.
#
# Runs under every awk there is here: AWK=... is what tigris-export uses.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
LC_ALL=C; export LC_ALL
W=`mktemp -d`
trap 'rm -rf "$W"' 0
X=$TIGER/tigris-export
fail=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }

cat > "$W/run.jsonl" <<'EOF'
{"type":"run","schema":1,"id":"run-x","tool":"tigris","version":"4.0.0, 2026.10.22.16.20","host":"box","os":"Linux","release":"7.0","arch":"x86_64","config":"./tigris.conf","profile":"server","start":"2026-11-01T10:00:00Z"}
{"type":"finding","level":"ALERT","id":"fsys004a","check":"check_suid","message":"/usr/local/bin/odd is setuid root and belongs to no package","controls":{"cis_v8":["4.1"],"nist_800_53":["AC-6","CM-7"],"iso_27001_2022":["8.2","8.18"],"cyber_essentials":["Secure configuration"]},"category":"filesystem"}
{"type":"finding","level":"FAIL","id":"lin016f","check":"check_network_config","message":"The system permits source routing from incoming packets","category":"network"}
{"type":"finding","level":"WARN","id":"ssh008w","check":"check_ssh","message":"sshd: x11forwarding is yes: X11 is forwarded","controls":{"cis_v8":["4.1","5.4"],"nist_800_53":["AC-17","IA-2"],"iso_27001_2022":["8.5","8.20"],"cyber_essentials":["Secure configuration","User access control"]},"category":"ssh"}
{"type":"finding","level":"INFO","id":"lin002i","check":"check_listeningprocs","message":"The process `sshd' is listening on socket 22 (TCP) on every interface.","category":"network"}
{"type":"finding","level":"ERROR","id":"init011e","check":"tigris","message":"--since needs the JSON report, and this run writes none","category":"tigris"}
{"type":"finding","level":"CONFIG","id":"con020c","check":"config","message":"The configuration directory holds two configuration files","category":"tigris"}
{"type":"finding","level":"WARN","id":"lin015w","check":"check_network_config","message":"The system has IP forwarding enabled","accepted":{"reason":"Docker \"needs\" it, really","until":"2026-12-31"},"category":"network"}
{"type":"finding","level":"FAIL","id":"upd003f","check":"check_updates","message":"3 security updates are waiting to be installed (apt).","detail":"libfoo, libbar\n\u0009and 1 more, said \"apt\"","accepted":{"reason":"=window on Friday","until":"-"},"category":"packages"}
{"type":"finding","level":"WARN","id":"fsys013w","check":"find_files","message":"=HYPERLINK(\"http://x.invalid\",\"click\") is a dangling symlink, with a back\\slash, an escape \u001b[31m, a return \u000d, caf\u00c3\u00a9, a lone \u00e9 and a tiger \u00f0\u009f\u0090\u0085.","category":"filesystem"}
{"type":"finding","level":"WARN","id":"fsys013w","check":"find_files","message":"+1+1 is a dangling symlink.","category":"filesystem"}
{"type":"finding","level":"WARN","id":"fsys013w","check":"find_files","message":"-rf is a dangling symlink.","category":"filesystem"}
{"type":"finding","level":"WARN","id":"fsys013w","check":"find_files","message":"@SUM(A1) is a dangling symlink.","category":"filesystem"}
{"type":"finding","level":"WARN","id":"fsys013w","check":"find_files","message":"\u0009tab is a dangling symlink.","category":"filesystem"}
{"type":"finding","level":"WARN","id":"zzz999w","check":"check_new","message":"something no metadata describes"}
{"type":"skip","check":"check_sudo","reason":"needs root"}
{"type":"future","note":"a record type this version does not know"}
{"type":"summary","id":"run-x","end":"2026-11-01T10:02:00Z","counts":{"ALERT":1,"FAIL":2,"WARN":8,"INFO":1,"ERROR":1},"skipped":1}
EOF
R=$W/run.jsonl

# every awk there is: the output must be the same bytes under each
awks=
for a in awk mawk gawk "busybox awk" original-awk
do
  command -v ${a%% *} >/dev/null 2>&1 || continue
  n=`echo "$a" | tr ' ' '-'`
  AWK=$a sh "$X" -f sarif "$R" > "$W/$n.sarif" 2> "$W/$n.err"; s1=$?
  AWK=$a sh "$X" -f csv "$R" > "$W/$n.csv" 2>> "$W/$n.err"; s2=$?
  [ $s1 -eq 0 ] && [ $s2 -eq 0 ] && [ ! -s "$W/$n.err" ] && [ -s "$W/$n.sarif" ] && [ -s "$W/$n.csv" ] ||
    { bad "$a: exit $s1 and $s2"; cat "$W/$n.err"; continue; }
  awks="$awks $n"
  cmp -s "$W/awk.sarif" "$W/$n.sarif" && cmp -s "$W/awk.csv" "$W/$n.csv" || { bad "$a writes something else than awk does"; continue; }
done
ok "converted under:$awks"
S=$W/awk.sarif; C=$W/awk.csv

# --- SARIF ---

# without python: the shape, by grep
grep -q '^{"\$schema":"https://json.schemastore.org/sarif-2.1.0.json","version":"2.1.0","runs":\[$' "$S" &&
  [ "`grep -c '^{"ruleId":' "$S"`" -eq 12 ] && [ "`grep -c '^{"id":' "$S"`" -eq 8 ] &&
  ok "SARIF 2.1.0: 12 results and 8 rules, one to a line" || bad "the SARIF's shape"
# the file is plain ASCII, like the report
[ -z "`tr -d '\11\12\40-\176' < "$S"`" ] && ok "the SARIF is plain ASCII" || bad "bytes outside ASCII in the SARIF"

# python: 0 when every assertion holds, 3 when only the official schema
# was not there to validate against
sarif_py() {
  python3 - "$@" <<'EOF'
import json, os, sys
d = json.load(open(sys.argv[1]))
mode = sys.argv[2]
assert d["version"] == "2.1.0" and d["$schema"].endswith("sarif-2.1.0.json")
assert len(d["runs"]) == 1
run = d["runs"][0]
drv = run["tool"]["driver"]
res = run["results"]
inv = run["invocations"][0]
# every result names a rule that is there, and says where
for r in res:
    assert drv["rules"][r["ruleIndex"]]["id"] == r["ruleId"], r
    assert r["level"] in ("error", "warning", "note", "none")
    assert r["message"]["text"]
    loc = r["locations"][0]
    assert loc["physicalLocation"]["artifactLocation"]["uri"]
    assert len(r["partialFingerprints"]["tigrisFinding/v1"]) == 16
if mode == "run":
    assert drv["name"] == "tigris" and drv["version"] == "4.0.0, 2026.10.22.16.20" and drv["semanticVersion"] == "4.0.0"
    assert drv["informationUri"].startswith("https://")
    assert run["automationDetails"]["id"] == "tigris/box/run-x"
    assert run["properties"] == {"host": "box", "os": "Linux", "release": "7.0", "arch": "x86_64",
                                 "config": "./tigris.conf", "profile": "server", "runId": "run-x"}
    assert inv["executionSuccessful"] is True and inv["machine"] == "box"
    assert inv["startTimeUtc"] == "2026-11-01T10:00:00Z" and inv["endTimeUtc"] == "2026-11-01T10:02:00Z"
    # the levels
    assert [(r["ruleId"], r["level"], r["properties"]["level"]) for r in res[:4]] == [
        ("fsys004a", "error", "ALERT"), ("lin016f", "error", "FAIL"),
        ("ssh008w", "warning", "WARN"), ("lin002i", "note", "INFO")]
    assert len(res) == 12 and [r["id"] for r in drv["rules"]] == [
        "fsys004a", "lin016f", "ssh008w", "lin002i", "lin015w", "upd003f", "fsys013w", "zzz999w"]
    # ERROR and the skipped check are the invocation's, CONFIG its configuration's
    n = inv["toolExecutionNotifications"]
    assert len(n) == 2 and n[0]["level"] == "error" and n[0]["descriptor"]["id"] == "init011e"
    assert n[0]["message"]["text"].startswith("--since needs")
    assert n[1]["level"] == "note" and n[1]["message"]["text"] == "check_sudo was skipped: needs root"
    c = inv["toolConfigurationNotifications"]
    assert len(c) == 1 and c[0]["level"] == "warning" and c[0]["descriptor"]["id"] == "con020c"
    assert not [r for r in res if r["ruleId"] in ("init011e", "con020c")]
    # the rule, from meta/ID
    ssh = drv["rules"][2]
    assert ssh["shortDescription"]["text"] == "X11Forwarding is yes."
    assert ssh["fullDescription"]["text"].startswith("X11Forwarding is yes. A forwarded X11 connection")
    assert ssh["help"]["text"].startswith("Fix: Set X11Forwarding no.\n\nX11Forwarding is yes.")
    assert ssh["help"]["text"].endswith("References: sshd_config(5)")
    assert ssh["helpUri"].endswith("/findings/ssh008w.html")
    assert ssh["defaultConfiguration"]["level"] == "warning"
    assert ssh["properties"]["category"] == "ssh" and ssh["properties"]["tags"] == ["security", "ssh"]
    assert ssh["properties"]["controls"] == {"cis_v8": ["4.1", "5.4"], "nist_800_53": ["AC-17", "IA-2"],
        "iso_27001_2022": ["8.5", "8.20"], "cyber_essentials": ["Secure configuration", "User access control"]}
    assert "controls" not in drv["rules"][1]["properties"]
    # lin002i is INFO here; its metadata says what it is at worst
    assert drv["rules"][3]["defaultConfiguration"]["level"] in ("note", "warning")
    new = drv["rules"][7]
    assert new["id"] == "zzz999w" and "fullDescription" not in new and "helpUri" not in new
    assert new["defaultConfiguration"]["level"] == "warning" and new["properties"] == {"tags": ["security"]}
    # the location: the check, on the host
    loc = res[2]["locations"][0]
    assert loc["physicalLocation"]["artifactLocation"]["uri"] == "check_ssh"
    assert loc["logicalLocations"] == [{"name": "check_ssh", "fullyQualifiedName": "box/check_ssh", "kind": "module"}]
    # accepted findings are suppressed, with the reason
    sup = [r for r in res if "suppressions" in r]
    assert [r["ruleId"] for r in sup] == ["lin015w", "upd003f"]
    assert sup[0]["suppressions"] == [{"kind": "external", "justification": 'Docker "needs" it, really',
                                        "properties": {"until": "2026-12-31"}}]
    assert sup[1]["suppressions"] == [{"kind": "external", "justification": "=window on Friday"}]
    # the detail follows the message
    assert sup[1]["message"]["text"] == '3 security updates are waiting to be installed (apt).\nlibfoo, libbar\n\tand 1 more, said "apt"'
    # every escape arrives as what it stood for, once; UTF-8 bytes are the character
    assert res[6]["message"]["text"] == ('=HYPERLINK("http://x.invalid","click") is a dangling symlink, with a back\\slash, '
        'an escape \x1b[31m, a return \r, caf\u00e9, a lone \u00e9 and a tiger \U0001f405.'), repr(res[6]["message"]["text"])
    assert res[10]["message"]["text"] == "\ttab is a dangling symlink."
    # one fingerprint per finding: the five fsys013w results are five alerts
    assert len(set(r["partialFingerprints"]["tigrisFinding/v1"] for r in res)) == 12
elif mode == "foreign":
    assert inv["executionSuccessful"] is False
    assert [r["level"] for r in res] == ["warning", "none", "warning", "warning"]
    t = res[0]["message"]["text"]
    assert t == "a bad \\q escape, a raw \u00e9 and \x1b, half a pair \ufffd, a whole one \U0001f405, a quote", repr(t)
    assert res[1]["ruleId"] == "../secret"
    assert "fullDescription" not in drv["rules"][res[1]["ruleIndex"]]
    assert res[2]["locations"][0]["physicalLocation"]["artifactLocation"]["uri"] == "a%20b%2F..%2Fc"
    assert res[3]["message"]["text"] == "cut sho"
elif mode == "nometa":
    assert all("fullDescription" not in r for r in drv["rules"]) and len(res) == 12
    assert drv["rules"][2]["properties"]["controls"]["cis_v8"] == ["4.1", "5.4"]
schema = os.environ.get("SARIF_SCHEMA", "")
if not schema:
    sys.exit(3)
try:
    import jsonschema
except ImportError:
    sys.exit(3)
jsonschema.validate(d, json.load(open(schema)), format_checker=jsonschema.FormatChecker())
EOF
}
havepy=N
command -v python3 >/dev/null 2>&1 && havepy=Y
official=
if [ $havepy = Y ]; then
  sarif_py "$S" run; st=$?
  case $st in
    0) ok "the SARIF parses and says what the report says"; official=Y ;;
    3) ok "the SARIF parses and says what the report says"; official=N ;;
    *) bad "the SARIF (python exit $st)" ;;
  esac
else
  echo "skip python3 is needed to parse the SARIF: only its shape was checked"
fi

# --- CSV ---

# An RFC 4180 reader: one line per field, "ROW.COL=value", a line break
# inside a field shown as <NL>; then how many rows, and the fewest and the
# most fields a row has
csvread() {
  ${AWK:-awk} '
    function emit() { col++; gsub(/\n/, "<NL>", cur); print row "." col "=" cur; cur = "" }
    BEGIN { row = 1; col = 0; cur = ""; inq = 0; min = 9999; max = 0 }
    {
      line = $0; n = length(line)
      if (inq) cur = cur "\n"
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (inq) {
          if (c != "\"") cur = cur c
          else if (substr(line, i + 1, 1) == "\"") { cur = cur c; i++ }
          else inq = 0
        }
        else if (c == "\"") inq = 1
        else if (c == ",") emit()
        else cur = cur c
      }
      if (!inq) { emit(); if (col < min) min = col; if (col > max) max = col; rows = row; row++; col = 0 }
    }
    END { print "rows=" rows " min=" min " max=" max " open=" inq }' "$1"
}
csvread "$C" > "$W/cells.txt"
has() { grep -q -x -F -e "$1" "$W/cells.txt"; }
TAB=`printf '\t'`

grep -q -x 'rows=15 min=12 max=12 open=0' "$W/cells.txt" && ok "CSV: a header and one row per finding record, twelve fields each" ||
  { bad "CSV rows and fields: `tail -1 "$W/cells.txt"`"; }
[ "`head -1 "$C"`" = "host,run,time,level,id,category,check,message,detail,accepted_reason,accepted_until,controls" ] &&
  ok "CSV: the header row" || bad "CSV header"
has '2.1=box' && has '2.2=run-x' && has '2.3=2026-11-01T10:00:00Z' && has '2.4=ALERT' && has '2.5=fsys004a' &&
  has '2.6=filesystem' && has '2.7=check_suid' && has '2.8=/usr/local/bin/odd is setuid root and belongs to no package' &&
  has '2.9=' && has '2.10=' && has '2.11=' &&
  ok "CSV: host, run, time, level, id, category, check and message of a row" || bad "CSV: the first finding's row"
has '4.12=cis_v8 4.1, 5.4; nist_800_53 AC-17, IA-2; iso_27001_2022 8.5, 8.20; cyber_essentials Secure configuration, User access control' &&
  has '3.12=' && ok "CSV: the controls in one column, by framework" || bad "CSV controls"
has '6.4=ERROR' && has '7.4=CONFIG' && has '15.5=zzz999w' && has '15.6=' &&
  ok "CSV: ERROR and CONFIG records are rows too; a finding with no category has an empty one" || bad "CSV: ERROR, CONFIG, no category"
has '8.10=Docker "needs" it, really' && has '8.11=2026-12-31' && ok "CSV: an accepted finding's reason and expiry, quotes and comma intact" || bad "CSV accepted"
has "9.9=libfoo, libbar<NL>${TAB}and 1 more, said \"apt\"" && ok "CSV: a detail keeps its lines, inside one quoted field" || bad "CSV detail"
has "9.10='=window on Friday" && has '9.11=' && ok "CSV: no expiry is an empty field, not a -" || bad "CSV accepted without expiry"
E9=`printf '\351'`; UTF=`printf 'caf\303\251'`; TIGERCHAR=`printf '\360\237\220\205'`
has "10.8='=HYPERLINK(\"http://x.invalid\",\"click\") is a dangling symlink, with a back\\slash, an escape \\u001b[31m, a return \\u000d, $UTF, a lone $E9 and a tiger $TIGERCHAR." &&
  ok "CSV: escapes decoded once, bytes above 127 as they were on disk, ESC and CR left written out" || { bad "CSV hostile message"; grep '^10\.8=' "$W/cells.txt" | od -c | head -12; }
  has "11.8='+1+1 is a dangling symlink." && has "12.8='-rf is a dangling symlink." &&
  has "13.8='@SUM(A1) is a dangling symlink." && has "14.8='${TAB}tab is a dangling symlink." &&
  has "6.8='--since needs the JSON report, and this run writes none" &&
  ok "CSV: a field that opens with = + - @ or a tab gets an apostrophe" || bad "CSV formula guard"
# and nothing else does: 7 guarded fields in all (six messages and a reason)
n=`grep -c "^[0-9]*\.[0-9]*='" "$W/cells.txt"`
[ "$n" -eq 7 ] && ok "CSV: only those are touched" || bad "CSV: $n fields start with an apostrophe, wanted 7"
[ -z "`tr -d '\15' < "$C" | cmp - "$C" 2>&1`" ] && ok "CSV: no carriage return reaches the file" || bad "a CR in the CSV"

if [ $havepy = Y ]; then
  python3 - "$C" <<'EOF' && ok "CSV: python's csv module reads the same" || bad "CSV through python's csv"
import csv, sys
rows = list(csv.reader(open(sys.argv[1], encoding="latin-1", newline="")))
assert len(rows) == 15 and all(len(r) == 12 for r in rows), [len(r) for r in rows]
assert rows[0][7] == "message" and rows[8][8] == 'libfoo, libbar\n\tand 1 more, said "apt"'
assert rows[7][9] == 'Docker "needs" it, really'
assert rows[9][7].startswith("'=HYPERLINK(\"http://x.invalid\",\"click\") is a dangling symlink, with a back\\slash")
assert rows[9][7].encode("latin-1").endswith(b"caf\xc3\xa9, a lone \xe9 and a tiger \xf0\x9f\x90\x85.")
for r in rows[1:]:
    for f in r:
        assert f[:1] not in ("=", "+", "-", "@", "\t", "\r"), f
EOF
fi

# --- a report no Tigris wrote ---

mkdir -p "$W/tree/meta" "$W/tree/systems"
cp "$X" "$W/tree/tigris-export"
echo "PLANTED-SECRET" > "$W/tree/secret"
{
  printf '%s\n' '{"type":"run","schema":1,"id":"r2","tool":"tigris","version":"x","host":"box","start":"yesterday"}'
  printf '{"type":"finding","level":"WARN","id":"abc001w","check":"c","message":"a bad \\q escape, a raw \351 and \033, half a pair \\ud83d, a whole one \\ud83d\\udc05, a quote"}\n'
  printf '%s\n' '{"type":"finding","level":"WEIRD","id":"../secret","check":"c","message":"an id that is a path"}'
  printf '%s\n' '{"type":"finding","level":"WARN","id":"abc002w","check":"a b/../c","message":"a check that is no file name","controls":{"cis_v8":["4.1",{"oops":1}]}}'
  printf '%s\n' 'not json at all' ''
  printf '%s' '{"type":"finding","level":"WARN","id":"abc003w","check":"c","message":"cut sho'
} > "$W/foreign.jsonl"
sh "$W/tree/tigris-export" -f sarif "$W/foreign.jsonl" > "$W/foreign.sarif" 2> "$W/foreign.err"; st=$?
[ $st -eq 0 ] && ! grep -q 'PLANTED-SECRET' "$W/foreign.sarif" && ok "an id that is a path opens no file" || bad "foreign report: exit $st, or the id was followed"
if [ $havepy = Y ]; then
  sarif_py "$W/foreign.sarif" foreign; st=$?
  case $st in 0|3) ok "a damaged report still comes out as valid SARIF, marked incomplete" ;; *) bad "foreign report's SARIF (python exit $st)" ;; esac
  [ $st -eq 0 ] || official=N
fi
sh "$W/tree/tigris-export" -f csv "$W/foreign.jsonl" > "$W/foreign.csv" 2>> "$W/foreign.err"
csvread "$W/foreign.csv" | grep -q -x 'rows=5 min=12 max=12 open=0' && ok "and as CSV with every row whole" || { bad "foreign CSV"; csvread "$W/foreign.csv" | tail -1; }

# --- without the metadata, the interface, the errors ---

mkdir "$W/bare"; cp "$X" "$W/bare/tigris-export"
( unset TIGERHOMEDIR; cd "$W/bare" && sh ./tigris-export -f sarif "$R" > "$W/bare.sarif" 2> "$W/bare.err" ); st=$?
[ $st -eq 0 ] && grep -q 'no meta directory found' "$W/bare.err" && ok "no meta directory: says so on stderr and still converts" || bad "no meta: exit $st"
if [ $havepy = Y ]; then
  sarif_py "$W/bare.sarif" nometa; st=$?
  case $st in 0|3) ok "its rules carry ids, categories and controls from the report" ;; *) bad "no-meta SARIF (python exit $st)" ;; esac
fi
( unset TIGERHOMEDIR; cd "$W/bare" && sh ./tigris-export -f csv "$R" 2> "$W/bare.err" | cmp -s - "$C" ) && [ ! -s "$W/bare.err" ] &&
  ok "the CSV needs no metadata and says nothing" || bad "CSV without meta"

echo "untouched" > "$W/out.file"
sh "$X" -f csv -o "$W/out.file" "$R" && cmp -s "$W/out.file" "$C" && ok "-o writes the file" || bad "-o"
sed 's/"schema":1,/"schema":2,/' "$R" > "$W/newer.jsonl"
echo "untouched" > "$W/out.file"
sh "$X" -f sarif -o "$W/out.file" "$W/newer.jsonl" > "$W/newer.out" 2> "$W/newer.err"; st=$?
[ $st -eq 2 ] && grep -q 'schema 2' "$W/newer.err" && [ ! -s "$W/newer.out" ] && [ "`cat "$W/out.file"`" = untouched ] &&
  ok "a newer schema is refused: exit 2, and -o's file is left as it was" || bad "newer schema: exit $st"
: > "$W/empty.jsonl"
sh "$X" -f sarif "$W/empty.jsonl" > "$W/empty.out" 2>/dev/null; st=$?
[ $st -eq 2 ] && [ ! -s "$W/empty.out" ] && ok "an empty file is not a report: exit 2, nothing written" || bad "empty report: exit $st"
sh "$X" -f xml "$R" > /dev/null 2>&1; s1=$?
sh "$X" "$R" > /dev/null 2>&1; s2=$?
sh "$X" -f csv "$W/nowhere.jsonl" > /dev/null 2>&1; s3=$?
sh "$X" -f csv -z "$R" > /dev/null 2>&1; s4=$?
[ "$s1$s2$s3$s4" = 2222 ] && ok "an unknown format, no format, a missing file, an unknown option: exit 2" || bad "error statuses $s1 $s2 $s3 $s4"
sh "$X" -h | grep -q 'tigris-export -f sarif|csv' && ok "-h shows the usage" || bad "-h"

mkdir -p "$W/site/log"
sed 's/run-x/run-old/' "$R" > "$W/site/log/security.report.box.261101-09:00.jsonl"
cp "$R" "$W/site/log/security.report.box.261101-10:00.jsonl"
( cd "$W/site" && sh "$X" -f csv ) | cmp -s - "$C" && ok "no file: the newest run in ./log" || bad "newest in ./log"
sh "$X" -f csv -l "$W/site/log" | cmp -s - "$C" && ok "-l names the log directory" || bad "-l"
mkdir "$W/nolog"
sh "$X" -f csv -l "$W/nolog" > /dev/null 2>&1; st=$?
[ $st -eq 2 ] && ok "a log directory with no report: exit 2" || bad "empty log directory: exit $st"
cp "$R" "$W/a=b.jsonl"
sh "$X" -f csv "$W/a=b.jsonl" | cmp -s - "$C" && ok "a report whose name has an = in it is read as a file" || bad "report named a=b"

# two reports end to end are two SARIF runs, each with its own rules
cat "$R" "$R" > "$W/two.jsonl"
sh "$X" -f sarif "$W/two.jsonl" > "$W/two.sarif"
[ "`grep -c '^{"tool":' "$W/two.sarif"`" -eq 2 ] && [ "`grep -c '^{"id":"ssh008w"' "$W/two.sarif"`" -eq 2 ] &&
  ok "two reports in one file are two runs" || bad "two runs"
if [ $havepy = Y ]; then
  python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); assert [len(r["results"]) for r in d["runs"]] == [12, 12]' "$W/two.sarif" &&
    ok "and still one valid document" || bad "two runs: the JSON"
fi

if [ $havepy = Y ]; then
  [ "$official" = Y ] && ok "validated against the official SARIF 2.1.0 schema ($SARIF_SCHEMA)" ||
    echo "skip the official SARIF 2.1.0 schema: set SARIF_SCHEMA to a copy of sarif-schema-2.1.0.json, with python3-jsonschema installed"
fi

[ $fail -eq 0 ] && echo "PASS" || { echo "--- stderr"; cat "$W"/*.err 2>/dev/null | head -20; echo FAIL; }
exit $fail
