# Solaris runner and fixture strategy (Phase D, Solaris leg)

> Backlogged 16 October 2026 in favour of mainstream work; the plan
> below stands for when it resumes.

How Tigris covers Solaris 11.4 on x86 without owning a Sun: the
macOS playbook a third time, plus something new — this host runs
QEMU with KVM, so a Solaris VM can validate what fixtures cannot.
AIX and the rest stay in the attic: AIX needs POWER hardware or
cloud time no free runner offers, and nobody here runs it. Read
this before writing any check under `systems/SunOS/`.

## OS recognition already works

`uname -s` on Solaris is `SunOS`, and `util/gethostinfo` has
passed it through since TIGER (`SunOS 5.11 i86pc` for an 11.4
x86 box: release from `$3`, architecture from `$5`). No mapping,
no changes; the `sunos` stub in `tests/fixtures/uname/` pins it
in `tests/hostinfo_check.sh`. `run_script` resolves
`systems/SunOS/default/` the same way it resolves every other
tree once `systems/SunOS/default/config` exists, which it does.

## Where Solaris checks live

`systems/SunOS/default/`, version-independent first, exactly
like the macOS and FreeBSD trees; an 11.x split earns a version
tree only on divergence. The config is the portable-tools one
with the export rule from `doc/macos-strategy.md` unchanged
(RM included: `delete()` needs it).

## Fixtures: files first, overrides for the rest

1. Files go through `TIGRIS_ROOT` unchanged: `/etc/passwd`,
   `/etc/shadow`, `/etc/user_attr` (root as a role),
   `/etc/security/audit_control`, `/etc/default/passwd`,
   `/etc/ssh/sshd_config`, `/etc/ipf/ipf.conf`, SMF
   manifests where they are files, crontabs, `/var/adm/messages`.
2. Live commands go through `Tigris_<Tool>_Cmd` overrides,
   documented in both tigris.confs: `Tigris_Svcs_Cmd` for `svcs`
   (service states), `Tigris_Pkg_Cmd` for `pkg list`
   (inventory only). PATH shadowing stays forbidden.

Candidate checks, in order: users and roles (uid 0 past root,
root not a role), password policy, sshd, the audit trail,
IP filter, SMF services that should not run, package
inventory, then the portable groups' Solaris halves. Anything
that cannot meet the fixture rule is cut and recorded, never
shipped half-testable.

## Deliberate cuts

- `pkg audit` phones home for its vulnerability database, and
  Tiger never phones home (the standing rule from Phases B
  and C). Inventory only.
- Kernel-state readings (kstat, live process tables) say
  `# Tigris: live system` like everywhere else; offline
  roots do not fake them.

## Live validation: a QEMU VM, not CI

No hosted CI runs Solaris. This host has `qemu-system-x86_64`
and `/dev/kvm`, so a Solaris 11.4 VM validates the checks
against the real thing: install once, snapshot, run the
fixture-proven checks live, compare. What is missing is the
media: the Oracle Solaris 11.4 ISO downloads under an OTN
license acceptance, which no script clicks through — that
fetch is a human step, reported, not worked around. Until it
lands, the fixture suites are the gate, as they were for
macOS and FreeBSD.

## Test goals for the Solaris leg (binding)

Every check ships with a fixture suite (positive, negative,
absent), ShellCheck and `sh -n` clean, explain/profile/
Controls green; releases move only with `all.sh` green on
Ubuntu AND the new suites green under all three awks, docs
updated, DocuVault closed with evidence. First green live-VM
run is recorded when it happens; nothing claims it before.
