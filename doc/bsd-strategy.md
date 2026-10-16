# BSD runner and fixture strategy (Phase C)

How Tigris covers FreeBSD first, then its siblings, without owning
a BSD rack: the macOS playbook, adjusted for an OS family that
starts further back. Read this before writing any check under
`systems/FreeBSD/`.

## OS recognition comes first

`util/gethostinfo` does not know the BSDs: their `uname -a` falls
through every branch and the OS comes back empty. FreeBSD,
OpenBSD and NetBSD each get a branch naming the OS after
`uname -s` (the SunOS precedent: no mapping, the kernel name is
the OS name), release from `$3`, architecture from `$NF`:

    else if($1 == "FreeBSD"){
        printf("FreeBSD %s %s\n", $3, $NF);
    }

`Tigris_Uname_Cmd` points `uname` at a stub, the way every other
tool override does; the BSD suites prove recognition through it.
Without this, no BSD tree resolves and every BSD check is dead.

## Where BSD checks live

`systems/FreeBSD/default/`, version-independent first, exactly
like `systems/MacOSX/default/`; OpenBSD and NetBSD split off
only when behavior diverges (different rc, different firewall
default). `run_script` needs no changes: it already resolves
`$OS/$REL/...` and falls back to `default` once `config` sets
`REL=default` from a `FreeBSD/default/config`. That config is the
Linux-shape one with the portable tools located and exported
(the export rule in `doc/macos-strategy.md` applies unchanged).

## Fixtures: files first, overrides for the rest

1. Files go through `TIGRIS_ROOT` unchanged: `/etc/rc.conf`
   (`KEY=value`, the whole rc model in one file),
   `/etc/newsyslog.conf`, `/etc/pf.conf`, crontabs, periodic.
2. Live commands go through `Tigris_<Tool>_Cmd` overrides,
   documented in both tigris.confs: `Tigris_Service_Cmd` for
   `service -e` (what is enabled), `Tigris_Pfctl_Cmd` for pf
   (the SAME variable the macOS check uses: one stub shape,
   two platforms), `Tigris_Ipfw_Cmd` for `ipfw show`,
   `Tigris_Pkg_Cmd` for `pkg info`. PATH shadowing stays
   forbidden: `config` resets PATH on BSD too.

## Deliberate cuts

- `pkg audit` phones home for its vulnerability database, and
  `Tiger` never phones home (the `softwareupdate`/`brew outdated`
  rule from Phase B). Package legs inventory what is installed;
  they do not match advisories.
- Offline `pkg` stays out: the database is SQLite and parsing it
  without sqlite3 invents a reader. Live `pkg info` plus stubs.
- `sysrc` reads the same rc.conf the check already reads; no
  override is added for it.

## CI

There is no GitHub-hosted FreeBSD runner. The BSD job runs the
live legs inside `vmactions/freebsd-vm` on `ubuntu-latest`,
asserting structural properties only (the report validates, the
live-only ids appear), never the runner's own posture. The
fixture suites run on Ubuntu like every other suite: a BSD check
that fails its fixtures on Ubuntu is broken, full stop. The
Gitea mirror cannot run either job; both are GitHub-only by
necessity, said so in the workflow. The job is proven when it
first runs green, not when it is written.

## Test goals for Phase C (binding)

The macOS goals carry over unchanged: every check ships with a
fixture suite (positive, negative, absent), ShellCheck and `sh
-n` clean, explain/profile/Controls green; releases move only
with `all.sh` green on Ubuntu AND the FreeBSD job green, docs
updated, DocuVault closed with evidence.

## Order of work

Recognition and this strategy unblock, in order: pf and ipfw
(one shadow reusing the pf override, one new), newsyslog and
the logging half, package inventory, then the BSD sides of
accounting, boot (rc) services and the portable groups. Anything
that cannot meet the fixture rule is cut and recorded, never
shipped half-testable.
