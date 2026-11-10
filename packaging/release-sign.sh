#!/bin/sh
#
# packaging/release-sign.sh - sign a release's artefacts with the maintainer key
#
#   sh packaging/release-sign.sh --key KEYID OUTDIR
#   TIGRIS_SIGN_KEY=KEYID sh packaging/release-sign.sh OUTDIR
#
# OUTDIR holds the release layout (release.yml builds it): src/, deb/,
# rpm/ and apk/ artefacts, packaging/ files, and a SHA256SUMS over all
# of them. The script first proves the sums hold, then writes a
# detached armored signature (.asc) beside SHA256SUMS and beside every
# artefact it names. The key is the maintainer's and is provided at
# signing time (a local secret key or a CI secret): no key material
# lives in this tree. Needs gpg and sha256sum. Users verify with
# packaging/verify-sigs.sh (doc/release-signing.md).
#
# 11/10/2026 - First release: the release's SHA256SUMS was generated
#             but unsigned, and nothing proved it held before upload.
#
LC_ALL=C; export LC_ALL

KEY=${TIGRIS_SIGN_KEY:-}
case "$1" in
  --key) KEY=${2:?usage: release-sign.sh [--key KEYID] OUTDIR}; shift 2;;
  -h|--help) echo "usage: release-sign.sh [--key KEYID] OUTDIR"; exit 0;;
esac
OUT=${1:?usage: release-sign.sh [--key KEYID] OUTDIR}

[ -n "$KEY" ] || { echo "release-sign.sh: no key: pass --key or set TIGRIS_SIGN_KEY (doc/release-signing.md)"; exit 1; }
[ -d "$OUT" ] || { echo "release-sign.sh: $OUT is not a directory"; exit 1; }
[ -f "$OUT/SHA256SUMS" ] || { echo "release-sign.sh: $OUT/SHA256SUMS is missing; the release builds it first"; exit 1; }
for t in gpg sha256sum; do
  command -v $t >/dev/null 2>&1 || { echo "release-sign.sh: $t is needed"; exit 1; }
done
gpg --batch --list-secret-keys "$KEY" >/dev/null 2>&1 || { echo "release-sign.sh: no secret key $KEY on this keyring"; exit 1; }

W=`mktemp -d`
trap 'rm -rf "$W"' 0

# Every name in SHA256SUMS must resolve to exactly one file under OUT:
# the release uploads the tree flat, so a name may sit at the top (a
# download dir) or one level down (the built tree: src/, deb/, ...).
LIST=$W/list
: > "$LIST"
while read -r sum name; do
  case "$sum" in ''|'#'*) continue;; esac
  [ -n "$name" ] || { echo "release-sign.sh: a SHA256SUMS line names nothing"; exit 1; }
  n=0; hit=
  for c in "$OUT/$name" "$OUT"/*/"$name"; do
    [ -f "$c" ] || continue
    n=$((n+1)); hit=$c
  done
  [ "$n" -eq 1 ] || { echo "release-sign.sh: $name resolves to $n files under $OUT"; exit 1; }
  printf '%s  %s\n' "$sum" "$hit" >> "$LIST"
done < "$OUT/SHA256SUMS"
[ -s "$LIST" ] || { echo "release-sign.sh: SHA256SUMS names nothing"; exit 1; }

# The sums hold before anything is signed: a signature over a broken
# set would bless the break.
sha256sum -c "$LIST" || exit 1

sign() {
  gpg --batch --yes --pinentry-mode loopback --armor --detach-sign \
    --local-user "$KEY" -o "$2" "$1" || exit 1
}
sign "$OUT/SHA256SUMS" "$OUT/SHA256SUMS.asc"
while read -r sum file; do
  sign "$file" "$file.asc"
done < "$LIST"

echo "release-sign.sh: signed SHA256SUMS and `wc -l < "$LIST"` artefacts"
