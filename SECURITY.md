# Security policy

## Supported versions

| Version | Supported |
| ------- | --------- |
| `master` | Yes |
| 3.9.0 | Yes |
| 3.8.1 and older, including all TIGER releases | No |

3.9.0 completes the fix 3.8.1 started: code execution on the auditing
machine when `tigris --root` audits a hostile image (3.5.0 to 3.8.1
are affected): upgrade if you audit images you did not build yourself.

Tigris is an independent fork. The official TIGER is maintained on
GNU Savannah; vulnerabilities in TIGER itself belong to its maintainer
and the distributions that ship it, not here.

## Reporting a vulnerability

Tigris runs as root, so a bug in it matters more than most. If you find
one, do not open a public issue. Report it privately, either through
[GitHub's private vulnerability reporting](https://github.com/creativeheadz/tigris/security/advisories/new)
or by mail to the maintainer at <a.trimbitas@oldforge.tech>. Say what
happens, how to reproduce it, and what you think the impact is; a
failing test case is welcome but not required.

You will get a first reply within a few days. Once the fix is agreed,
it lands on `master` with a test, the advisory is published, and you
are credited unless you would rather not be. Fixes that also apply to
TIGER are offered back to Savannah and the Debian bug tracker, as with
any other fix.

## Scope notes

A finding Tigris misses, or one it reports wrongly, is a bug, not a
vulnerability in Tigris: open a normal issue for it. The checks are
auditors, not enforcement; see [the roadmap](ROADMAP.md) for what each
release promises.
