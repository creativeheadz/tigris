#!/bin/sh
#
# packaging/verify-sigs.sh - prove a release's checksums and signatures
#
#   sh packaging/verify-sigs.sh DIR [PUBKEY]
#   sh packaging/verify-sigs.sh --self-test
#
# DIR holds a release's files beside its SHA256SUMS (a download dir:
# the release uploads every artefact flat). The script proves the sums
# hold, then proves each .asc beside them with gpgv against PUBKEY
# (the maintainer's public key). A .asc with no PUBKEY, or a PUBKEY
# that is not the signer's, fails: checksums alone authenticate
# nothing. Needs sha256sum, and gpgv where signatures are checked.
# --self-test runs the positive and negative cases on throwaway
# fixtures (its GPG keys live in a mktemp dir and never leave it)
# and skips the GPG cases where gpg or gpgv is missing.
#
# 11/10/2026 - First release: with release-sign.sh, the verify half.
#
LC_ALL=C; export LC_ALL

case "$0" in */*) SELF=$0;; *) SELF=./$0;; esac

verify_dir() {
  dir=$1; ring=$2
  [ -f "$dir/SHA256SUMS" ] || { echo "verify-sigs.sh: $dir/SHA256SUMS is missing"; return 1; }
  ( cd "$dir" && sha256sum -c SHA256SUMS ) || return 1
  n=0
  for s in "$dir"/*.asc; do
    [ -f "$s" ] || continue
    f=${s%.asc}
    [ -f "$f" ] || { echo "verify-sigs.sh: $s has no file beside it"; return 1; }
    [ -n "$ring" ] || { echo "verify-sigs.sh: $s is signed but no PUBKEY was given (doc/release-signing.md)"; return 1; }
    command -v gpgv >/dev/null 2>&1 || { echo "verify-sigs.sh: gpgv is needed to check $s"; return 1; }
    gpgv --keyring "$ring" "$s" "$f" || return 1
    n=$((n+1))
  done
  if [ "$n" -eq 0 ]; then
    echo "verify-sigs.sh: checksums hold; nothing is signed (no .asc in $dir)"
  else
    echo "verify-sigs.sh: checksums hold and $n signatures verify"
  fi
}

self_test() {
  command -v sha256sum >/dev/null 2>&1 || { echo "SKIP: sha256sum is missing"; return 2; }
  W=`mktemp -d`
  trap 'rm -rf "$W"' 0
  failed=0
  pass() {
    label=$1; shift
    if "$@" >/dev/null 2>&1; then echo "ok   $label"; else echo "FAIL $label"; failed=1; fi
  }
  must_fail() {
    label=$1; shift
    if "$@" >/dev/null 2>&1; then echo "FAIL $label (passed, should fail)"; failed=1; else echo "ok   $label"; fi
  }

  mkdir "$W/good"
  echo "tigris one" > "$W/good/one.tar.gz"
  echo "tigris two" > "$W/good/two.deb"
  ( cd "$W/good" && sha256sum one.tar.gz two.deb > SHA256SUMS )
  pass "clean checksums verify" sh "$SELF" "$W/good"

  mkdir "$W/tampered"
  cp "$W/good/one.tar.gz" "$W/good/two.deb" "$W/good/SHA256SUMS" "$W/tampered/"
  printf 'x' >> "$W/tampered/two.deb"
  must_fail "a tampered byte fails" sh "$SELF" "$W/tampered"

  mkdir "$W/short"
  cp "$W/good/one.tar.gz" "$W/good/SHA256SUMS" "$W/short/"
  must_fail "a missing file fails" sh "$SELF" "$W/short"

  mkdir "$W/nosums"
  cp "$W/good/one.tar.gz" "$W/nosums/"
  must_fail "missing SHA256SUMS fails" sh "$SELF" "$W/nosums"

  if command -v gpg >/dev/null 2>&1 && command -v gpgv >/dev/null 2>&1; then
    SIGN=${SELF%/*}/release-sign.sh
    [ -f "$SIGN" ] || { echo "FAIL release-sign.sh is not beside $SELF"; return 1; }
    mkkey() {
      GNUPGHOME=$1; export GNUPGHOME
      mkdir -m 700 "$1"
      gpg --batch --pinentry-mode loopback --passphrase '' \
        --quick-gen-key "$2" rsa2048 sign never >/dev/null 2>&1 || return 1
      gpg --batch --export "$2" > "$3" || return 1
    }
    if mkkey "$W/g1" tigris-test-one "$W/ring1.gpg" && mkkey "$W/g2" tigris-test-two "$W/ring2.gpg"; then
      mkdir "$W/signed"
      cp "$W/good/one.tar.gz" "$W/good/two.deb" "$W/good/SHA256SUMS" "$W/signed/"
      GNUPGHOME=$W/g1; export GNUPGHOME
      pass "release-sign.sh signs the set" \
        sh "$SIGN" --key tigris-test-one "$W/signed"
      unset GNUPGHOME
      pass "the signer's key verifies" sh "$SELF" "$W/signed" "$W/ring1.gpg"
      must_fail "the wrong key fails" sh "$SELF" "$W/signed" "$W/ring2.gpg"
      must_fail "no key for a signed set fails" sh "$SELF" "$W/signed"
      printf 'x' >> "$W/signed/one.tar.gz"
      must_fail "a tampered byte fails signed too" sh "$SELF" "$W/signed" "$W/ring1.gpg"
    else
      echo "FAIL the throwaway GPG keys did not generate"
      failed=1
    fi
  else
    echo "SKIP the GPG cases (gpg or gpgv is missing)"
  fi

  [ "$failed" -eq 0 ] && echo PASS
  return $failed
}

case "$1" in
  --self-test) self_test; exit $?;;
  -h|--help) echo "usage: verify-sigs.sh DIR [PUBKEY] | verify-sigs.sh --self-test"; exit 0;;
esac
command -v sha256sum >/dev/null 2>&1 || { echo "verify-sigs.sh: sha256sum is needed"; exit 1; }
[ -n "$1" ] || { echo "usage: verify-sigs.sh DIR [PUBKEY] | verify-sigs.sh --self-test"; exit 1; }
[ -d "$1" ] || { echo "verify-sigs.sh: $1 is not a directory"; exit 1; }
[ -n "$2" ] && [ ! -f "$2" ] && { echo "verify-sigs.sh: $2 is not a file"; exit 1; }
verify_dir "$1" "$2"
exit $?
