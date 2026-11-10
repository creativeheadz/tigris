# Release signing

Every release artefact is verifiable: checksums users can recompute,
and maintainer signatures over those checksums and every artefact.
Before this, the release attached an unsigned `SHA256SUMS`, the `.apk`
was signed by a throwaway CI key nobody could name, and nothing proved
the sums held before upload. The pieces:

- `packaging/release-sign.sh` signs a built release (maintainer key,
  provided at signing time: never in this tree).
- `packaging/verify-sigs.sh` proves a download: sums hold, signatures
  verify against the maintainer's public key.
- `packaging/keys/` holds the maintainer's public halves (`.rsa.pub`
  for abuild, `.gpg` for GPG): trust anchors, committed.
- `make dist-sums` / `make verify-sums` roll and prove a source
  tarball's sums from the tree.

`release.yml` is untouched by this change (another packet owns it);
the exact hunks that wire signing into it are filed at the end.

## Maintainer keys

No maintainer key is committed yet. Provisioning is a maintainer
task, done once, offline:

1. GPG: on an offline machine, `gpg --full-generate-key` (RSA 4096,
   no expiry comments needed), note the fingerprint, export the
   public half to `packaging/keys/tigris-release.gpg`
   (`gpg --export ADDRESS > packaging/keys/tigris-release.gpg`) and
   commit that file. Record the fingerprint below.
2. abuild: on an offline Alpine, `abuild-keygen -a -n -q`, commit only
   the `.rsa.pub` it writes to `~/.abuild/` as
   `packaging/keys/<address>.rsa.pub`. Record the fingerprint below
   (`openssl dgst -sha256` over the `.rsa.pub`).
3. Keep both private halves offline. At release time the GPG private
   half reaches CI only as the `TIGRIS_SIGN_KEY` secret (armored
   export) with its key id in `TIGRIS_SIGN_KEY_ID`, and the abuild
   private half only as the `TIGRIS_ABUILD_KEY` secret; or sign
   locally and upload by hand.

Fingerprints (empty until provisioned):

| key                                | fingerprint |
|------------------------------------|-------------|
| GPG `tigris-release.gpg`           | _TBD_       |
| abuild `<address>.rsa.pub`         | _TBD_       |

CI refuses private halves: `packaging/keys/*.rsa` (without `.pub`)
and any key block fail the lint job.

## Release flow

1. `release.yml` builds the `.deb`, `.rpm` and `.apk`, the source
   tarball, and `SHA256SUMS` over all of them, as today.
2. Signing (the hunks below): import `TIGRIS_SIGN_KEY`, run
   `sh packaging/release-sign.sh "$RUNNER_TEMP/out"`, which first
   proves the sums hold and then writes `.asc` beside `SHA256SUMS`
   and every artefact.
3. Verification, in the same job: flatten the tree to a temp dir and
   run `sh packaging/verify-sigs.sh "$flat" packaging/keys/tigris-release.gpg`,
   which is exactly what a user runs.
4. Upload artefacts, `SHA256SUMS`, and every `.asc`.

The `.apk` needs its own key through the Alpine container: with
`TIGRIS_APK_RELEASE=1`, the `TIGRIS_ABUILD_KEY` secret written to the
builder's `~/.abuild/`, and the committed `.rsa.pub` copied beside it
(public, so the mounted tree provides it), `packaging/ci.sh apk`
builds with `mkapk.sh --release`, which proves the key matches
`packaging/keys/` and never keygens. Without that env var CI keeps
the throwaway dev key (`--throwaway-key`).

## Verifying a download

Fetch the release's files and `SHA256SUMS` into one directory, and
the maintainer's GPG public key (from the release assets or
`packaging/keys/tigris-release.gpg` in the tree; check its
fingerprint against the table above first):

```sh
sha256sum -c SHA256SUMS
sh verify-sigs.sh . tigris-release.gpg
```

(`verify-sigs.sh` is `packaging/verify-sigs.sh` in the tree.)
Checksums alone authenticate nothing: a `.asc` with no key, or the
wrong key, fails. `gpgv` is the only new tool a verification needs,
and it ships with GPG on every base system.

## The SKIP windows

Two committed files say `SKIP` by necessity, not neglect:

- `packaging/APKBUILD` carries `sha512sums="SKIP"`: the tarball it
  sums is built from the working tree at build time
  (`mkapk.sh` runs `abuild checksum`), so no committed sum could
  match it. The release's own `APKBUILD` (with the tag tarball's
  sum) is generated at release time and is itself checksummed and
  signed.
- `packaging/PKGBUILD` carries its `sha256sums` at `SKIP` until the
  tag tarball exists; the commit after the release fills it
  (`packaging/README.md`). CI builds the AUR package from a tree
  tarball with sums skipped for the same reason the tag does not
  exist yet.

## Rotation

New key, same dance: generate offline, commit the new public half
beside the old (both verify old releases), record the fingerprint,
move the secrets over, sign one release with both if the overlap
matters, then remove the old public half in a later commit that says
so. Never reuse a retired fingerprint row: strike it, do not delete.

## Appendix: the release.yml hunks

Filed, not applied: this packet may not edit `release.yml`. Against
the workflow as of 11/10/2026:

```diff
 --- a/.github/workflows/release.yml
 +++ b/.github/workflows/release.yml
 @@ -113,6 +113,17 @@
            ( cd "$out" && sha256sum src/* deb/* rpm/* apk/* packaging/* | sed 's|  [a-z]*/|  |' > SHA256SUMS )
            cat "$out/SHA256SUMS"
 +      - name: Sign the sums and the artefacts
 +        env:
 +          TIGRIS_SIGN_KEY_ID: ${{ secrets.TIGRIS_SIGN_KEY_ID }}
 +          TIGRIS_SIGN_KEY: ${{ secrets.TIGRIS_SIGN_KEY }}
 +        run: |
 +          printf '%s' "$TIGRIS_SIGN_KEY" | gpg --batch --import
 +          TIGRIS_SIGN_KEY="$TIGRIS_SIGN_KEY_ID" sh packaging/release-sign.sh "$RUNNER_TEMP/out"
 +      - name: Prove the release verifies as users will
 +        run: |
 +          rm -rf "$RUNNER_TEMP/flat" && mkdir -p "$RUNNER_TEMP/flat"
 +          cp "$RUNNER_TEMP"/out/src/* "$RUNNER_TEMP"/out/deb/* "$RUNNER_TEMP"/out/rpm/* "$RUNNER_TEMP"/out/apk/* "$RUNNER_TEMP"/out/packaging/* "$RUNNER_TEMP"/out/SHA256SUMS* "$RUNNER_TEMP/flat/"
 +          sh packaging/verify-sigs.sh "$RUNNER_TEMP/flat" packaging/keys/tigris-release.gpg
        - name: Attest the packages and the tarball
```

```diff
 @@ -125,4 +136,4 @@
        - name: Attach them to the release
          env:
            GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
 -        run: gh release upload "$GITHUB_REF_NAME" "$RUNNER_TEMP"/out/src/* "$RUNNER_TEMP"/out/deb/* "$RUNNER_TEMP"/out/rpm/* "$RUNNER_TEMP"/out/apk/* "$RUNNER_TEMP"/out/packaging/* "$RUNNER_TEMP"/out/SHA256SUMS --clobber
 +        run: gh release upload "$GITHUB_REF_NAME" "$RUNNER_TEMP"/out/src/* "$RUNNER_TEMP"/out/deb/* "$RUNNER_TEMP"/out/rpm/* "$RUNNER_TEMP"/out/apk/* "$RUNNER_TEMP"/out/packaging/* "$RUNNER_TEMP"/out/SHA256SUMS "$RUNNER_TEMP"/out/SHA256SUMS.asc "$RUNNER_TEMP"/out/*/*.asc --clobber
```

The release `.apk`, when the abuild key is provisioned: `ci.sh`
already switches to `mkapk.sh --release` on `TIGRIS_APK_RELEASE=1`
and stages the key itself, so the hunk only mounts the secret:

```diff
 -          docker run --rm -v "$PWD:/tiger:ro" -v "$RUNNER_TEMP/out/apk:/out" alpine:latest sh /tiger/packaging/ci.sh apk /out
 +          printf '%s' "${{ secrets.TIGRIS_ABUILD_KEY }}" > "$RUNNER_TEMP/builder.rsa"
 +          docker run --rm -v "$PWD:/tiger:ro" -v "$RUNNER_TEMP/out/apk:/out" -v "$RUNNER_TEMP/builder.rsa:/builder.rsa:ro" \
 +            -e TIGRIS_APK_RELEASE=1 -e TIGRIS_ABUILD_KEY_FILE=/builder.rsa alpine:latest sh /tiger/packaging/ci.sh apk /out
 +          rm -f "$RUNNER_TEMP/builder.rsa"
```

(The key file sits beside `$RUNNER_TEMP/out`, never inside it, so it
cannot be uploaded; it is removed right after. The release notes line
that tells users to verify against `SHA256SUMS` should then name the
signatures too.)
