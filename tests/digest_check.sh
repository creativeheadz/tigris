#!/bin/sh
#
# tests/digest_check.sh - the hash helpers compute the right digests
#
# c/md5.c and c/snefru.c (the signature and setuid-integrity checks use
# bin/snefru when built; md5 is the fallback of -G and util/mksig)
# declared their 32-bit word as unsigned long, which is 64 bits on every
# current machine, so every digest was wrong and those checks could never
# match a signature. Builds both here and compares with the reference
# values: MD5("abc") from RFC 1321, Snefru-256 of "\n" and "1\n" from the
# vectors in snefru.c's own header. Needs a C compiler; says so and passes
# without one.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
CC=${CC:-cc}
command -v "$CC" >/dev/null 2>&1 || { echo "ok   (no C compiler here: nothing to test)"; echo PASS; exit 0; }
W=`mktemp -d`
trap 'rm -rf "$W"' 0
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

$CC -O2 -o "$W/md5" "$TIGER/c/md5.c" 2>"$W/err" || { bad "md5.c does not build: `head -2 "$W/err"`"; echo FAIL; exit 1; }
$CC -O2 -o "$W/snefru" "$TIGER/c/snefru.c" 2>"$W/err" || { bad "snefru.c does not build: `head -2 "$W/err"`"; echo FAIL; exit 1; }

r=`"$W/md5" -sabc | sed -n 's/.*= //p'`
[ "$r" = 900150983cd24fb0d6963f7d28e17f72 ] && ok "MD5(abc) = 900150983cd24fb0d6963f7d28e17f72" || bad "MD5(abc) = $r"
r=`printf 'abc' | "$W/md5" | tr -d ' \n'`
case "$r" in *900150983cd24fb0d6963f7d28e17f72*) ok "MD5 of standard input agrees" ;; *) bad "MD5 of stdin: $r" ;; esac
# (c/snefru.c is built with OUTPUT_BLOCK_SIZE 8, the 256-bit output; the
# vectors are the ones in its own header, under "./snefru256")
r=`printf '\n' | "$W/snefru" | tr -s ' ' | sed 's/^ //'`
[ "$r" = "2e02687f 0d45d5b9 b50cb68c 3f33e684 3d618a1a ca2d0689 3d3eb4e3 026b5732" ] &&
  ok "Snefru-256 of a newline matches the vector in snefru.c" || bad "Snefru-256(\\\\n) = $r"
r=`printf '1\n' | "$W/snefru" | tr -s ' ' | sed 's/^ //'`
[ "$r" = "bfea4a05 a2a2ef15 c736d114 598a20b9 d9bd4d66 b661e6b0 5ecf6a77 37bdc58c" ] &&
  ok "Snefru-256 of 1 and a newline matches too" || bad "Snefru-256(1\\\\n) = $r"

[ $fail -eq 0 ] && echo PASS || echo FAIL
exit $fail
