#!/bin/sh
#
# tests/schema_check.sh - the JSON report against doc/tigris-report.schema.json
#
#   tests/schema_check.sh               check the schema itself
#   tests/schema_check.sh FILE.jsonl    also validate every line of FILE
#
# Without a file: valid samples of each record must pass and broken ones
# must be rejected, so the schema cannot quietly become permissive; and
# the object tigris-diff -j prints must validate. With a file (the smoke
# test passes a real run's): every line must validate, the first must be
# the run record and the last the summary with the same id.
#
# Needs Python with the jsonschema package; exits 2 (skip) without it.
# PYTHON overrides the interpreter.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
PYTHON=${PYTHON:-python3}
"$PYTHON" -c 'import jsonschema' 2>/dev/null || { echo "SKIP: $PYTHON with the jsonschema package is needed"; exit 2; }

W=`mktemp -d`
trap 'rm -rf "$W"' 0
fail=0

"$PYTHON" - "$TIGER/doc/tigris-report.schema.json" "$1" <<'EOF' || fail=1
import json, sys
from jsonschema import Draft202012Validator

schema = json.load(open(sys.argv[1]))
Draft202012Validator.check_schema(schema)
v = Draft202012Validator(schema)
bad_count = 0

def ok(label, rec):
    errs = list(v.iter_errors(rec))
    print(("ok   " if not errs else "FAIL ") + label + ("" if not errs else ": " + errs[0].message[:90]))
    return not errs

def rejected(label, rec):
    errs = list(v.iter_errors(rec))
    print(("ok   " if errs else "FAIL ") + label)
    return bool(errs)

run = {"type": "run", "schema": 1, "id": "r1", "tool": "tigris", "version": "3.2.4", "host": "h",
       "os": "Linux", "release": "7.0", "arch": "x86_64", "config": "./tigerrc", "start": "2026-10-05T07:12:03Z"}
finding = {"type": "finding", "level": "WARN", "id": "ssh008w", "check": "check_ssh", "message": "m"}
summary = {"type": "summary", "id": "r1", "end": "2026-10-05T07:14:01Z",
           "counts": {"ALERT": 0, "FAIL": 1, "WARN": 2, "INFO": 3, "ERROR": 0},
           "distinct": {"ALERT": 0, "FAIL": 1, "WARN": 1},
           "categories": {"ssh": {"ALERT": 0, "FAIL": 1, "WARN": 2, "INFO": 0, "ERROR": 0},
                           "logging": {"ALERT": 0, "FAIL": 0, "WARN": 0, "INFO": 3, "ERROR": 0}},
           "score": {"value": 95, "formula": "100 - 10*ALERT - 4*FAIL - 1*WARN",
                     "deducted": {"ALERT": 0, "FAIL": 4, "WARN": 1}},
           "skipped": 0}
results = [
    ok("a run record", run),
    ok("a finding", finding),
    ok("a finding with detail and an accepted block", dict(finding, detail="a\nb", accepted={"reason": "r", "until": "2027-01-31"})),
    ok("an acceptance with no expiry", dict(finding, accepted={"reason": "r", "until": "-"})),
    ok("a summary", summary),
    ok("a record with a field the schema does not know (forward compatibility)", dict(finding, future="x")),
    ok("a finding with a seven-letter prefix, as TIGER's rootkit and rootdir ids have", dict(finding, id="rootkit001f", level="FAIL")),
    rejected("a run without the schema version", {k: v_ for k, v_ in run.items() if k != "schema"}),
    rejected("a newer schema version than this file describes", dict(run, schema=2)),
    rejected("a finding with an unknown level", dict(finding, level="NOTICE")),
    rejected("a finding with a malformed id", dict(finding, id="boot06")),
    rejected("a finding without a message", {k: v_ for k, v_ in finding.items() if k != "message"}),
    rejected("an acceptance with a badly formatted date", dict(finding, accepted={"reason": "r", "until": "1/2/2027"})),
    rejected("an acceptance without a reason", dict(finding, accepted={"until": "-"})),
    rejected("a summary missing a level in its counts", dict(summary, counts={"ALERT": 0, "FAIL": 0, "WARN": 0, "INFO": 0})),
    rejected("a summary with a score above 100", dict(summary, score=dict(summary["score"], value=101))),
    rejected("a summary with a category missing a level", dict(summary, categories={"ssh": {"ALERT": 0, "FAIL": 1, "WARN": 2, "INFO": 0}})),
    rejected("a timestamp without the Z", dict(run, start="2026-10-05T07:12:03")),
]
if not all(results):
    sys.exit(1)

if len(sys.argv) > 2 and sys.argv[2]:
    lines = [l for l in open(sys.argv[2], encoding="ascii") if l.strip()]
    recs = [json.loads(l) for l in lines]
    errs = [(i + 1, e.message[:100]) for i, r in enumerate(recs) for e in v.iter_errors(r)]
    for n, m in errs[:5]:
        print("FAIL line %d: %s" % (n, m))
    ok_file = not errs
    ok_file &= recs[0]["type"] == "run" and recs[-1]["type"] == "summary" and recs[0]["id"] == recs[-1]["id"]
    print(("ok   " if ok_file else "FAIL ") + "%s: %d records validate, run first and summary last with the same id" % (sys.argv[2].rsplit("/", 1)[-1], len(recs)))
    if not ok_file:
        sys.exit(1)
EOF

# the object tigris-diff -j prints
mkdir -p "$W/log"
cat > "$W/a.jsonl" <<'EOF'
{"type":"run","schema":1,"id":"a","tool":"tigris","version":"3.2.4","host":"h","os":"Linux","release":"7.0","arch":"x86_64","start":"2026-10-05T07:00:00Z"}
{"type":"finding","level":"WARN","id":"ssh004w","check":"check_ssh","message":"one"}
{"type":"summary","id":"a","end":"2026-10-05T07:01:00Z","counts":{"ALERT":0,"FAIL":0,"WARN":1,"INFO":0,"ERROR":0}}
EOF
cat > "$W/b.jsonl" <<'EOF'
{"type":"run","schema":1,"id":"b","tool":"tigris","version":"3.2.4","host":"h","os":"Linux","release":"7.0","arch":"x86_64","start":"2026-10-05T08:00:00Z"}
{"type":"finding","level":"WARN","id":"dev004w","check":"check_devices","message":"two"}
{"type":"summary","id":"b","end":"2026-10-05T08:01:00Z","counts":{"ALERT":0,"FAIL":0,"WARN":1,"INFO":0,"ERROR":0}}
EOF
sh "$TIGER/tigris-diff" -j "$W/a.jsonl" "$W/b.jsonl" | head -1 > "$W/diff.jsonl"
"$PYTHON" - "$TIGER/doc/tigris-report.schema.json" "$W/diff.jsonl" <<'EOF' || fail=1
import json, sys
from jsonschema import Draft202012Validator
v = Draft202012Validator(json.load(open(sys.argv[1])))
errs = list(v.iter_errors(json.loads(open(sys.argv[2]).read())))
print(("ok   " if not errs else "FAIL ") + "tigris-diff -j validates" + ("" if not errs else ": " + errs[0].message[:90]))
sys.exit(1 if errs else 0)
EOF

[ $fail -eq 0 ] && echo "PASS"
exit $fail
