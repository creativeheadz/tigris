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

`release.yml` wires it in (the sign step, the prove step, the
`.asc` and public-key upload, the abuild key mount): the wiring is
described at the end.

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

## Appendix: the release.yml wiring

Applied. After the sums step, `release.yml` signs and proves:

- **Sign the sums and the artefacts**: imports `TIGRIS_SIGN_KEY`
  and runs `sh packaging/release-sign.sh "$RUNNER_TEMP/out"`,
  which first proves the sums hold.
- **Prove the release verifies as users will**: flattens the tree
  (artefacts, their `.asc` files, `SHA256SUMS*`) and runs
  `sh packaging/verify-sigs.sh "$flat" packaging/keys/tigris-release.gpg`.
- **Attach them to the release**: uploads the artefacts,
  `SHA256SUMS`, `SHA256SUMS.asc`, every artefact `.asc`, and
  `packaging/keys/tigris-release.gpg` (the key users verify with).
- The `.apk` build mounts the abuild private half from the
  `TIGRIS_ABUILD_KEY` secret at `/builder.rsa` (beside
  `$RUNNER_TEMP/out`, never inside it, removed right after) with
  `TIGRIS_APK_RELEASE=1`, so `ci.sh` builds with `mkapk.sh
  --release`, which proves the key matches `packaging/keys/`.

All of it fails closed without the provisioned keys and secrets
above: no silent throwaway keys on the release path.
