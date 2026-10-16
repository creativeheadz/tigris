# Packaging

`tigris` builds as a `.deb`, an `.rpm` and an `apk` in CI, installs
beside the distribution's `tiger` without sharing a file with it, and
ships as an AUR package and a COPR. The container image (Dockerfile)
is the fourth artifact. Debian packaging of the fork is for later and
would be its own package.

## Layout

`make install` follows the Tiger paths (`tiger` in sbin, `$prefix/tiger`,
`/etc/tigris`); the distro tree is reshaped from it, not forked from it:

| install                    | package                                   |
|----------------------------|-------------------------------------------|
| sbin `tiger tigercron tigris-explain` (+`tigris*`) | sbin keeps `tigris tigris-diff tigris-accept`; the rest move to the library dir |
| `$prefix/tiger`            | `/usr/lib/tigris` (`/usr/lib64` on 64-bit rpms) |
| `/etc/tigris`, `/var/.../tiger` | `/etc/tigris`, `/var/lib/tigris`, `/var/log/tigris` |
| `tigris explain` beside sbin | baked library path, as `make install` bakes the others |
| `tigris-diff`, `tigris-accept` defaults | rewritten to the tigris directories |
| six man pages              | the three `tigris` ones (`-doc` split on Alpine) |
| Perl `check_network`       | dropped: undispatched, and it would pull a perl dependency |

`packaging/stage.sh` does the reshaping; every rewrite asserts its
source text, so a source change that moves it fails the build. The
package needs nothing beyond libc and the base system.

## Building

Each format builds from the working tree (uncommitted changes
included), never dirtying the checkout:

```sh
sh packaging/mkdeb.sh /tmp/out     # needs dpkg-dev, gcc, make
sh packaging/mkrpm.sh /tmp/out     # needs rpm-build, gcc, make
sh packaging/mkrpm.sh --srpm /tmp/out   # the source rpm, for COPR
sh packaging/mkapk.sh /tmp/out     # on Alpine, as a builder user (see below)
```

`packaging/smoke-installed.sh` runs the installed package as root: the
entry points, a real `-E` run, `--since`, and the diff and accept
defaults. CI builds all four formats, installs each in its container
and runs the smoke; the `.deb` job also installs Debian's `tiger`
beside it.

The AUR `PKGBUILD` builds from the release tag tarball instead of the
tree, as AUR requires. CI validates the same file against a tarball of
the tree (on a release commit CI may run before the tag exists) and
checks the committed `.SRCINFO` still matches. `.SRCINFO` is generated,
never edited: `makepkg --printsrcinfo > .SRCINFO` after touching
`PKGBUILD`.

Builders that refuse root need a user first. Alpine:

```sh
apk add abuild tar gzip sudo
adduser -D builder; addgroup builder abuild
echo 'builder ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
su builder -c 'sh packaging/mkapk.sh /tmp/out'
```

Arch:

```sh
pacman -Sy --noconfirm base-devel sudo
useradd -m builder; echo 'builder ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
```

## Releases

Before a release, `sh util/mkeol` refreshes `systems/Linux/2/eol_list`,
the end of each distribution release's security support that
check_release judges against (from endoflife.date; it needs the
network, which an audit never does).

Each release bumps the version where the formats carry it literally:

- `version` (as today), and the `Version` in `packaging/tigris.spec`
  with its `_tag`, `Source0` and `%changelog` entry;
- `pkgver` in `packaging/PKGBUILD` and `.SRCINFO`, with `sha256sums`
  at `SKIP`: the tag's tarball does not exist before the tag. Once it
  does, the commit after the release puts its sum in
  (`curl -sL .../version_X_Y_Z.tar.gz | sha256sum`), regenerates
  `.SRCINFO` (`makepkg --printsrcinfo`, in an Arch container if need
  be), and that pair is what goes to the AUR;
- the `.deb` (from `version`) and the `.apk` (stamped at build) follow
  on their own.

The release workflow attaches the `.deb`, the `.rpm` and both `.apk`
files to the GitHub release. COPR takes the source rpm
(`copr-cli build tigris tigris-<version>-1.*.src.rpm`, or a dist-git
webhook once wired); the AUR package is pushed from `PKGBUILD` and
`.SRCINFO` (`git push` to `aur.archlinux.org:tigris.git`). Both need
Andrei's accounts, so both stay manual.
