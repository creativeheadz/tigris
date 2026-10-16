# macOS fixture and runner strategy (Phase B)

How Tigris checks macOS without owning a Mac on every desk: the same
two mechanisms Phase A proved on Linux, plus one CI job. Read this
before writing any check under `systems/MacOSX/`.

## Where macOS checks live

`util/gethostinfo` reports Apple systems as OS `MacOSX`, so
`run_script` resolves them under `systems/MacOSX/...` automatically:
most specific (`MacOSX/<REL>/<REV>/<ARCH>`) wins, falling back to
`systems/MacOSX/default/` and then `systems/default/`. Ship
version-independent checks in `systems/MacOSX/default/` first and add
a version tree only when Apple moves behavior between releases. `tiger`
gets dispatch blocks for the new checks behind `Tigris_Check_*` gates,
exactly like the Linux ones; `tigris.conf` and `tigris-quick.conf` carry the
toggles identically, or `profile_check.sh` fails.

## Fixtures without a Mac

Two kinds of input, two mechanisms. Nothing else is allowed.

1. Files (plists, configs, `/etc`, `/var/db`) go through
   `TIGRIS_ROOT` and `rootfile`, exactly as on Linux. Suites build
   fixture roots the same way. No change needed.
2. macOS-only live commands (`csrutil`, `fdesetup`,
   `system_profiler`, `pkgutil`, `dscl`, `launchctl`, `profiles`,
   `spctl`, `pmset`, `diskutil`, `pwpolicy`) go through per-tool
   overrides: `Tigris_Csrutil_Cmd`, `Tigris_Fdesetup_Cmd`, and so on,
   defaulting to empty, meaning the real tool. This mirrors
   `Tigris_SSHD_Cmd` (check_ssh) and `Tigris_Mount_Probe_Cmd`
   (documented in tigris.conf). Every override gets a commented-out
   documented line in both tigris.confs. Suites point the variables at
   fixture scripts under `tests/fixtures/macos/` through the suite
   tigris.conf.

Four rules with teeth, all learned the hard way:

- The OS config (`systems/MacOSX/default/config`) must export every
  tool variable the checks need: checks run as children of the
  configured shell and inherit only what is exported. Unexported
  means the check sees nothing (init001e).

- NEVER shadow `PATH` to fake a tool: `config` resets PATH to
  `/sbin:/usr/sbin:/bin:/usr/bin`, so a fake earlier in PATH never
  reaches the check. The override variable is the only door.
- `Tigris_Sysctl_Root` is meaningless on macOS (there is no
  `/sys` or `/proc`): live macOS state arrives only through the
  `_Cmd` overrides. Fixture trees for it would lie about the
  platform; do not build them.
- A check that cannot judge from files plus overridden commands
  stays live-only and says so (`# Tigris: live system`), or it does
  not ship. macOS binaries are never executed on Linux CI.

## CI

GitHub Actions gains a macOS job (`macos-15` or newer): it runs the
whole `tests/all.sh` (fixture suites run anywhere) plus live legs
that assert structural properties only — the report validates, the
JSON parses, expected live-only ids appear — never specific
findings, which depend on the runner's own posture. The Gitea mirror
cannot run macOS runners, so the macOS job is GitHub-only by
necessity; say so in the workflow, the way `release.yml` already
does for the registry. Ubuntu CI stays the fixture gate: a macOS
check that fails its fixture suite on Ubuntu is broken, full stop.

## Test goals for Phase B (binding)

No macOS check ships without: a fixture suite with positive,
negative, and absent legs; ShellCheck and `sh -n` clean; explain,
profile, and Controls gates green; a live macOS CI leg where the
check reads live state. Before any release containing macOS work:
full `all.sh` green on Ubuntu AND the macOS job green, `doc/`
updated (meta prose, parity matrix, ROADMAP boxes), DocuVault
tasks closed with evidence. The release tag moves only then.

## Order of work

This strategy unblocks, in order: SIP status, FileVault, doas (one
check each, all override-driven); macOS package and application
inventory (files plus `pkgutil`/`system_profiler` overrides); then
the macOS side of every portable group. If a planned check cannot
meet the fixture rule above, it is cut and recorded in
`doc/parity-matrix.md` like prelink and DB2 were — never shipped
half-testable.
