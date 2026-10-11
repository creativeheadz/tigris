#!/bin/sh
#
# tests/site_check.sh - the website util/mksite builds
#
# Builds it into a temporary directory and checks: a page for every
# finding id and every framework, the index, the rendered documents and
# the files they need; every link from one page of it to another leads
# to a file that is there (anchors on the same page included); no markdown
# left unrendered (a stray ** or a [text](url)); and text from meta/ is
# escaped, so a < in an explanation cannot open a tag. Needs no network.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

sh "$TIGER/util/mksite" "$W/site" > "$W/out" 2>&1 || { bad "mksite failed:"; cat "$W/out"; echo "FAIL"; exit 1; }
S=$W/site

for f in index.html json-format.html metadata.html style.css findings/index.html compliance/index.html \
  compliance/cis.html compliance/nist.html compliance/iso.html compliance/ce.html \
  schema/tigris-report.schema.json art/banner.png art/tiger.png art/social.png
do
  [ -s "$S/$f" ] || bad "missing: $f"
done
[ $fail -eq 0 ] && ok "the index, the documents, the four frameworks and their files"

nids=`ls "$TIGER/meta" | wc -l`
npages=`ls "$S/findings" | grep -cv '^index.html$'`
[ "$nids" -eq "$npages" ] && ok "a page for each of the $nids finding ids" || bad "$npages finding pages for $nids ids"

# every link inside the site leads somewhere: href and src that are not
# URLs, resolved from the page's directory; #anchors looked up in the page
find "$S" -name '*.html' | while read -r page
do
  d=${page%/*}
  grep -o '\(href\|src\)="[^"]*"' "$page" | sed 's/^[a-z]*="//; s/"$//' | sort -u |
  while read -r l
  do
    case "$l" in http:*|https:*|mailto:*) continue ;; esac
    target=${l%%#*}; frag=
    case "$l" in *'#'*) frag=${l#*#} ;; esac
    if [ -z "$target" ]; then t=$page
    else
      t=$d/$target
      case "$t" in */) t=${t}index.html ;; esac
      [ -d "$t" ] && t=$t/index.html
    fi
    [ -e "$t" ] || { echo "${page#$S/}: $l"; continue; }
    [ -n "$frag" ] && ! grep -q "id=\"$frag\"" "$t" && echo "${page#$S/}: $l (no such anchor)"
  done
done > "$W/broken"
[ -s "$W/broken" ] && { bad "broken links inside the site:"; head -20 "$W/broken"; } || ok "every link inside the site leads to a page and anchor that exist"

# markdown left as it was
grep -l '\*\*[A-Za-z]' "$S"/*.html > "$W/stars"
grep -l '\]([a-z#]' "$S"/*.html | grep -v 'schema' >> "$W/stars"
[ -s "$W/stars" ] && { bad "markdown not rendered in:"; cat "$W/stars"; } || ok "no markdown left unrendered"

# a meta text with a < and & in it comes out escaped
m=`grep -l '<' "$TIGER"/meta/* | head -1`
if [ -n "$m" ]; then
  id=${m##*/}
  grep -q '&lt;' "$S/findings/$id.html" && ok "text from meta/ is escaped ($id)" || bad "$id: a < in its text not escaped"
fi
grep -q '<code>tigris explain upd003f</code>' "$S/findings/upd003f.html" && grep -q 'href="upd002w.html"' "$S/findings/upd003f.html" &&
  ok "a finding's page names its command and links the ids its text mentions" || bad "upd003f's page"
grep -q 'id="c-7-3"' "$S/compliance/cis.html" && grep -q 'href="../compliance/cis.html#c-7-3"' "$S/findings/upd003f.html" &&
  ok "controls link to their framework page, and back" || bad "control links"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
