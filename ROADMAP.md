# Roadmap

Tigris is a security auditor for Linux, descended from TIGER (Texas A&M,
1993). The goal is to make it the auditor people pick on purpose: at
full functional parity with Lynis, and better where it counts. Lynis
is the reference point because it is the tool people compare against:
everything Lynis checks on a platform Tigris supports, Tigris checks
too, tracked group by group in `doc/parity-matrix.md`.

*Last updated 10 October 2026.* `[x]` done, `[ ]` to do, `[~]` started.
Everything marked done is on `master`; "released" means tagged (the last
tag is `version_3_8_1`).

## Contents

1. [Ground rules and decisions](#ground-rules-and-decisions)
2. [Where things stand](#where-things-stand)
3. [Principles](#principles)
4. [What has shipped](#what-has-shipped)
5. [3.2.x: maintenance](#32x-maintenance)
6. [3.3: modern Linux baseline](#33-modern-linux-baseline)
7. [4.0: where Tigris beats Lynis](#40-where-tigris-beats-lynis)
8. [Parity with Lynis](#parity-with-lynis)
9. [Ideas parked for later](#ideas-parked-for-later)
10. [Windows (after 4.0)](#windows-after-40)
11. [Engineering, ongoing](#engineering-ongoing)
12. [Not planned](#not-planned)

## Ground rules and decisions

Settled, so they do not have to be argued again:

- **Tigris is an independent fork.** The official TIGER stays on GNU
  Savannah, maintained by Javier Fernández-Sanguino Peña, who also
  maintains the Debian package. Fixes here that apply to TIGER are
  offered back as patches (to Savannah and the Debian bug tracker);
  three went to the BTS on 4 October 2026 (#1111306, #505906, #610785).
  A Savannah membership is pending.
- **The history stays whole.** The full TIGER history is kept, with its
  authors, and the copyright notices stay on the files. Tigris adds to
  that line; it does not rewrite it.
- **Licence: GPL-2.0-or-later**, as TIGER. `c/md5.c` (RSA) and
  `c/snefru.c` (Xerox) carry their own notices.
- **Lynis is a list of ideas, not a source of code.** Lynis is GPL-3.0;
  copying from it would force Tigris to GPL-3.0 and take away the
  "or later" that keeps it the more permissive of the two. Checks are
  written from the documentation of the thing being checked, and the
  parity target is tracked by test group, never by copying tests.
- **Parity with Lynis is the coverage target.** Everything Lynis checks
  on a platform Tigris supports, Tigris checks too, group by group in
  `doc/parity-matrix.md`. Deliberate exceptions (no live probing,
  retired legacy, no copied code) are recorded in that file and stay
  exceptions, not drift.
- **Linux first, then the rest in phases.** The other Unixes (AIX,
  HP-UX, IRIX, NeXT, SunOS, Tru64, UNICOS, Mac OS X) are in the
  `attic/other-unix-2026-10` tag and come back in platform phases with
  a maintainer and a CI runner for each: macOS, then the BSDs, then
  Solaris and AIX. Linux parity comes first.
- **Internal names stay for now.** `tigerrc`, the `Tiger_*` settings, the
  `tiger` command and `/etc/tiger` keep working. They change at 4.0, with
  compatibility shims, in one go. `./tigris` is the entry point today.

## Where things stand

|                      | Tigris 3.8.1 (October 2026)                                     | Lynis 3.1.7 (June 2026)                  |
|----------------------|-----------------------------------------------------------------|------------------------------------------|
| Language             | POSIX shell, no dependencies                                    | POSIX shell                              |
| Licence              | GPL-2.0-or-later                                                | GPL-3.0                                  |
| Checks               | 97 check scripts, 520 finding ids in 15 categories, each explained | ~470 test ids in 42 categories        |
| Platforms            | Linux: Debian/Ubuntu, Fedora/RHEL/SUSE, Alpine, Arch            | Linux, macOS, BSD, Solaris, AIX          |
| Machine output       | JSON Lines with a versioned schema, next to the text report     | `report.dat` (key=value)                 |
| Explanations         | `tigris explain ID`, one metadata file per id (severity, category, checks) | Suggestions linked to the CISOfy website |
| Compliance mapping   | CIS v8, NIST 800-53, ISO 27001:2022, Cyber Essentials, per finding, in the JSON                          | Enterprise (paid) edition only |
| Change over time     | `tigris-diff` and `tigris-accept`; `tigercron`                  | Mostly point-in-time                     |
| Package integrity    | dpkg, rpm, apk, pacman, one finding id per kind of problem      | Limited                                  |
| Offline audit        | `tigris --root`: every check reads an image except the ten that need the running system, nothing in it is run; a container image with every distribution's package tools | None |
| Tests                | 103 fixture suites, 19 CI jobs on every push                     | No per-check suite found in the repository |
| Lynis parity         | Linux groups covered in Phase A (see below); macOS, BSD, Solaris-AIX ride the platform phases | 43 test groups across Linux, macOS, BSD, Solaris |

Lynis is broad, maintained and popular (16k GitHub stars). Tigris
meets it group for group without copying it test for test, and wins
on depth, on output other tools can use, on honest evidence, and on
engineering quality.

**Measured** on the reference machine (Linux Mint 22.3 desktop, kernel 7.0,
12 threads, 62 GB, a 1.8 TB root disk and a 3.6 TB data disk holding
1.9 TB, 2.4k packages), run as root on an otherwise idle machine:

| | 3.2.4 as released | 3.6.0, full | 3.6.0, `--profile quick` | 3.7.0, full | 3.7.0, `--profile quick` |
|---|---|---|---|---|---|
| Report | 49,651 lines; 24 checks refused to run | 343 lines: 13 FAIL, 70 WARN | 285 lines: 13 FAIL, 47 WARN | 334 lines: 13 FAIL, 64 WARN | 291 lines: 13 FAIL, 48 WARN |
| Wall time | 7:16 | 2:01 | 1:01 | 2:00 | 1:03 |
| CPU (user + system) | not recorded | 104 s + 85 s | 60 s + 37 s | 104 s + 85 s | 62 s + 38 s |
| Peak memory | 159 MB | 131 MB | 131 MB | 131 MB | 131 MB |

3.3.0 took 1:58 and 34.6 MB full, 0:58 and 13.9 MB quick; 3.4.0 took
1:58 and 134 MB full, 1:02 and 134 MB quick; 3.5.0 took 1:59 and
134 MB full, 1:00 quick. The 131 MB is apt-get mapping its package
cache for under a second. An offline audit of a Debian 13 image with
systemd and sshd took 9 seconds and 67 MB in 3.5.0, about 10 seconds
in 3.6.0, and 12 seconds and 8 MB in 3.7.0. The 3.7.0 image was
exported from a container (no package cache to map); its 3.6.0 audit
took 6 seconds, before the 16 checks that read it now. A browser was
open during the 3.7.0 runs; 3.6.0 re-measured the same morning gave
the same numbers within two seconds.

3.4.0's peak is apt-get mapping its package cache for under a second
when check_updates asks what is waiting; without that check the quick
run peaks at 32 MB (the docker CLI, asked by check_containers).

The full run took 3:11 when a second run was reading the same disks, and
up to 3:21 on 5 October while other services were busy. Everything except
the filesystem scan finishes in about a minute; the scan is bound by how
fast the disks can be walked (a bare `find` over the same disks takes
146 s on a busy day), which is why the quick profile leaves it out.

## Principles

1. **POSIX shell, no dependencies.** It runs as root, so the people who
   run it should be able to read it. It must also run on minimal
   containers and rescue systems. No rewrite in another language.
2. **Every finding is complete.** A stable id, a severity, a message,
   why it matters, how to fix it (commands, not just advice), references,
   and the compliance controls it maps to.
3. **One id means one thing everywhere.** `lin005f` is "an installed file
   differs from its package" whether the package is a `.deb`, an RPM, an
   apk or a pacman package, so a program reading the report needs no
   per-distribution knowledge.
4. **Machine-readable output from the start.** JSON comes out of the same
   code path as the text report, never bolted on.
5. **Read-only and offline by default.** Tigris never changes the system
   and never touches the network unless asked.
6. **No check ships without a test.** Each check must catch a planted
   problem and stay quiet on a clean system, in a real container where
   the check depends on a real package manager.
7. **Lean.** It must run well on a Raspberry Pi or a 512 MB VPS, not just
   a workstation. Every release records wall time, CPU and peak memory on
   the reference machine; a change that makes them worse needs a reason.
   No check spawns a process per file when one pass will do, and the file
   system scan stays the only thing allowed to take minutes.
8. **Honest evidence.** A finding says what was found and where. A check
   that cannot run says so, and does not guess. Noise is a bug: a report
   with 16,000 lines of dangling symlinks hides the few that matter.

## What has shipped

**Released: 3.8.1 (10 October 2026).** A security release: a hostile
image audited with `--root` could run a command as root on the auditing
machine, through values its checks parsed as shell code (3.5.0 to 3.8.0
are affected). Nothing read from a system is parsed as code now, and
`tests/hostile_root_check.sh` keeps it so. Also a Fix and References
for every finding, the last 87 findings mapped to controls, and ten
bug fixes from the review of 10 October. The full list is in `CHANGES`.

**Released: 3.4.0 (7 October 2026).** Twelve new checks for how a Linux
system is run today, profiles, a non-root mode that says what it
skipped, and one metadata file per finding id; two incompatible changes
(the exit status, and nine ids that gained their level's letter). The
full list is in `CHANGES`.

**Released: 3.3.0 (7 October 2026).** The first release as Tigris:
everything in the lists below, from running properly on a modern Linux to
the JSON report and drift. The full list is in `CHANGES`.

**Released: 3.2.4 (4 October 2026).** Finishes the 3.2.4 release candidate
TIGER left in 2018 and folds in the five Debian non-maintainer uploads
that never reached the repository. Debian bugs #1111306 (merged-/usr),
#505906 (prelink, md5sum parsing), #610785 (`Tiger_FSScan_PruneDirs`),
#1105709 (parallel install), #1033743 (Romanian translation).

**In 3.3.0** (on master since 3.2.4):

*Runs properly on a modern Linux.*
- [x] `sudo ./tigris` works from a checkout; the tree-ownership guard
  explains itself (`init010e`) and accepts the sudo user's own checkout.
- [x] `config` falls back to the generic Linux checks correctly on a
  kernel newer than the version symlinks. Before, every Linux-specific
  check silently did not run on kernel 7.
- [x] The filesystem scan is one `find` with `-fprintf`, not an `ls | awk`
  per file (about a million processes before); the old path stays for
  busybox.
- [x] Dangling symlinks and unusual file names are listed one by one only
  under system directories (`Tiger_FSScan_DetailDirs`); elsewhere one line
  per directory. Image stores (Flatpak, Docker, containerd, snap) are
  pruned by default (`Tiger_FSScan_PruneDirs`).
- [x] Checks taught the modern world: PAM-era PATH and umask, systemd,
  merged-/usr, `nologin` service accounts, `/var/log/syslog` and the
  journal, `/dev` as udev builds it, `su` and `passwd` being setuid.
- [x] `egrep`, `tempfile` and `which` are gone; `util/realpath` replaces
  the C helper when it is not built; distribution detection reads
  `/etc/os-release`.
- [x] The dead-service checks retired and deleted: inetd, xinetd and
  tcpd, rhosts and `.netrc`, anonymous FTP and ftpusers, printcap,
  OmniBack, NIS+, inittab and the static Debian advisory list
  (17 files). The boot check stays: despite its name it covers GRUB 2.
  So does `check_known`'s inetd backdoor test, which costs nothing when
  there is no inetd.
- [x] `tigerrc-quick`: everything except the filesystem scan, about a
  minute where the full run takes three (62 s on the reference desktop, 175 lines).

*New checks.*
- [x] `check_sysctl`: kernel pointer and log restriction, Yama, ASLR,
  SysRq, BPF, perf, `fs.protected_*`, IPv6 redirects and source routing,
  and the kernel's own verdict on CPU speculation flaws.
- [x] `check_ssh` reads the effective configuration with `sshd -T`: 15
  directives and the cipher, MAC and key-exchange lists.
- [x] `check_systemd`: sandboxing of network-facing services, scored by
  `systemd-analyze security`, naming the three protections that would
  help most.
- [x] `pkg_integrity`: package integrity for rpm, apk and pacman, with
  the finding ids the dpkg checks use, plus `lin038w` (mode or owner
  differs from the package). Honours pacman's `NoExtract` and
  `NoUpgrade`. Verified on Fedora, Rocky 9, openSUSE, Alpine and Arch.
- [x] The dpkg checks: merged-/usr aware, deleted files reported again,
  one `grep` for diversions instead of a `dpkg -S` each (130 MB to 11 MB).

*Output and drift.*
- [x] JSON Lines report from `message()` itself: run record, one record
  per finding, summary with counts. A `schema: 1` version, a JSON Schema
  (`doc/tigris-report.schema.json`), the contract in `doc/json-format.md`,
  and CI validating a real run against it.
- [x] `tigris-diff`: new, resolved and unchanged between two runs, exit 1
  on anything new, `-j` for JSON. When either run skipped the filesystem
  scan (the quick profile) its `fsys*` findings are set aside on both
  sides instead of showing as resolved, and different `tigerrc` files are
  noted; the run record carries `filesystem_scan` for this.
- [x] `tigris-accept`: acknowledge a finding with a reason and an expiry;
  out of the text report, marked in the JSON, back when it expires.
- [x] Every message id on a live Linux path is well-formed and
  explained: 308 emitted, 308 with entries, the count complete for the
  first time. 22 explanations written this week (apache, aide, NTP,
  permissions, root, rootkit, suid/sgid, crack, PATH); three
  placeholder ids replaced with real ones (`tigxxxx` to `tig001e`,
  `suidxxx` to `suid002`, `miscxxxx` to `pass022w`); the NIS+ check
  that held the last four malformed ids retired. `tigexp` serves them
  all and `tests/explain_check.sh` fails CI on any gap.

*Engineering.*
- [x] 12 fixture suites and a CI pipeline of 11 jobs: syntax and
  ShellCheck, a full run on Ubuntu, the dpkg checks on Debian stable,
  sid and Ubuntu 24.04, and the package checks on five other
  distributions.
- [x] The other Unixes moved to the attic tag (364 files).
- [x] `SECURITY.md`, issue templates and a contributing guide, with
  GitHub's private vulnerability reporting switched on so the route the
  policy names actually works.

**In 3.4.0** (on master since 3.3.0):
- [x] **Exit status** from the worst finding: 0 nothing at WARN or
  above, 2 a check could not run, 3 WARN, 4 FAIL, 5 ALERT; 1 still means
  the audit did not run. Accepted findings do not count. An incompatible
  change for anything that expected 0: it goes in the next release's
  notes as such.
- [x] **`tigris --since RUN`** (a `.jsonl` report or `last`) prints only
  what changed and takes its status from the new findings; `-q` now
  silences the run itself, so `tigris -q --since last` in cron mails
  only when something changed.
- [x] A check `run_script` cannot run (`misc005e`, `misc024e`,
  `misc025e`) is a `message()` now, so it is in the JSON and shows in a
  diff instead of its findings silently looking resolved.
- [x] `tigris-diff` marks a new finding that is already accepted and
  does not count it for its exit status.
- [x] ShellCheck blocks the build (see 3.2.x).
- [x] `check_listeningprocs`: sockets on ports in the kernel's ephemeral
  range are one finding per process, protocol and address, with the
  ports in the detail. Browsers and Syncthing hold UDP sockets on ports
  that change every run; with the port in the message, the first real
  `--since` run on the reference desktop reported 9 of them as new. Also: a root
  listener on every interface was reported as a WARN and again as an
  INFO (`&& message || message`, and `message()` returns non-zero).
  `tests/listening_check.sh` feeds `lsof -F` fixtures (`Tiger_LSOF_Cmd`).
- [x] **`check_firewall`**: is incoming traffic denied unless something
  accepts it, for IPv4 and IPv6 separately. Reads the kernel's ruleset
  (`nft list ruleset`, and the legacy iptables tables when they are
  loaded), so it works the same for nft, iptables-nft, ufw and
  firewalld; a default-deny is a chain on the input hook with policy
  drop or an unconditional drop or reject as its last rule (firewalld
  ends with a reject). Never runs nft or iptables unless their tables
  are already in the kernel (both would load modules). Replaces
  `lin019f`, which compared `iptables -nL` with an empty table: Docker's
  rules made it pass on the reference desktop while INPUT accepted everything, and an
  nftables-only firewall made it fail. Fixtures captured from real
  rulesets in containers with their own network namespace (ufw on
  Ubuntu, firewalld on Fedora, nft on Debian); 15 assertions.
- [x] `check_listeningprocs` reports IPv6 listeners. It kept only lsof's
  IPv4 records, so a daemon on `[::]` or on a dual-stack socket was never
  seen (on the reference desktop: Syncthing's sync port, 22000); the netstat fallback cut
  `:::22` at the first colon and misread every `udp6` line. The sockets
  now come from `ss` when there is one (iproute2, on every current
  distribution, where lsof often is not), then lsof, then netstat. A
  process on `0.0.0.0` and on `::` is one finding, `::1` is loopback,
  and the user is each process's effective uid from `/proc`, as lsof
  has it, so the findings do not depend on the tool: on the reference desktop ss and
  lsof give the same 12. A host without lsof no longer gets an
  `init001e` error from the check when netstat is there.
  `tests/listening_check.sh` has fixtures for all three tools and
  passes under mawk, gawk and busybox awk.
- [x] **`check_firewall` reports the ports Docker publishes.** Docker
  rewrites their destination in prerouting and forwards them, so they
  never reach the input hook: with ufw enabled in a container, a
  listener on the host did not answer from outside and the published
  port did, while fire003i said incoming traffic was denied. Each port
  published on every address (or on one non-loopback address) is a
  WARN (fire005w) unless something may restrict it: rules in
  DOCKER-USER other than Docker's own `return`, or a forward chain of
  the host's own that drops, which give one INFO per family (fire006i)
  since what they match is not evaluated. Read from the ruleset already
  taken, for Docker's iptables backend (the nat `DOCKER` chain, as
  `dnat to` or nft's `xt target "DNAT"`) and its nftables backend
  (`docker-bridges`); on a host without nft (Ubuntu ships iptables-nft
  alone) from `iptables -S`, only while Docker runs, since listing a nat
  table that does not exist creates it. On the reference desktop: Immich's 2283 over
  IPv4. Fixtures from the reference desktop and docker:dind (Docker 29.8.2 with both
  backends, 27.5.1, ufw); `tests/firewall_check.sh` makes 28
  assertions, under mawk, gawk and busybox awk.
- [x] **`deb_statoverride`** (lin039w): on Debian and Ubuntu, files whose
  mode or owner differs from what `dpkg-statoverride` sets for them
  (crontab and plocate setgid, the D-Bus launch helper, `/etc/ssl/private`),
  with the chown and chmod that restore them. It is what remains of
  `lin038w` for dpkg, which records no other modes. Silent on the reference desktop, whose
  six overrides all match; `tests/statoverride_check.sh` needs no root,
  and `tests/deb_checks.sh` plants a real override in Debian stable, sid
  and Ubuntu 24.04. `Tiger_Deb_StatOverride` turns it off.
- [x] **Finding metadata.** Each id the code can emit has `meta/ID`: its
  severity (the levels the code really uses: lin002i is also a WARN),
  one of 15 categories, the checks that report it, references, and the
  explanation, moved from `doc/*.txt`. `tigris explain ID` (still
  `tigexp` underneath) reads it directly, so there is no index to
  rebuild as root, and shows it as written instead of through `fmt`,
  which ran indented examples together. Every JSON finding carries its
  `category` (an added field, schema 1 unchanged). `make` builds one
  HTML page, `doc/explanations.html`, from it. The 210 explanations of
  ids nothing emits any more (inetd, anonftp, rhosts, the Solaris and
  HP-UX checks) were dropped; they are in `doc/*.txt` at the tag
  `version_3_3_0`. `tests/explain_check.sh` fails on an emitted id with
  no file, a file for an id nothing emits, an unknown key or category,
  a severity that leaves out a level the code reports, or a Check list
  that does not match the scripts the id appears in.
- [x] **Every id names one level** (incompatible: nine ids change, so
  the release notes must list them). `pathmsg` reported the ids its
  callers gave it without a level letter (`ali003`, `suid002`), at FAIL,
  WARN or INFO as the file deserved, so a run that hit one wrote JSON
  the schema rejects. It now adds the letter: `ali003`, `ali007` and
  `cron002` become `...w` or `...i`; `ali004`, `ali008`, `cron003` and
  `suid002` become `...f`, `...w` or `...i`; `path006` and `path007`
  become `path011w/i` and `path012f/w/i`, new numbers because
  `path006w` and `path007w` meant other things in older versions. A
  report from 3.3.0 compared with one from 3.4.0 shows those findings
  as resolved and new once. `tests/pathmsg_check.sh` covers the levels.
- [x] **`check_secureboot`**: Secure Boot from the firmware's SecureBoot
  and SetupMode variables (off: boot009w; setup mode, where anything can
  enrol keys: boot011w; on: boot012i; legacy BIOS: boot010i), and, when
  it is on, kernel lockdown: a verified kernel that is not locked down
  lets root load unsigned code into it (lin040w). Says nothing in a
  container, whose /sys/firmware is empty. The reference desktop: on, lockdown
  integrity. `tests/secureboot_check.sh` builds a /sys per case.
- [x] **`check_mac`**: AppArmor or SELinux enforcing (mac003i, with
  AppArmor's profiles counted by mode and the complain ones named), or
  not: neither active, or AppArmor with no profile enforced (mac001w),
  SELinux permissive (mac002w). Complain-mode profiles are not a finding
  of their own, since Ubuntu ships several that way (Transmission,
  LibreOffice on the reference desktop). **`check_audit`**: auditd running (aud001w), with
  rules (aud002w, aud003i), and logs kept across reboots: journald's
  Storage= as systemd resolves journald.conf and its drop-ins, or a
  syslog daemon (logf008w). The reference desktop: AppArmor enforcing 26 profiles, no
  auditd, journal on disk.
- [x] **`check_timesync`**: a time daemon running (time001w), only one
  (time004w), and the clock synchronised (time002w, time003i): chronyc
  tracking for chronyd, which marks the kernel clock synchronised only
  with rtcsync, timedatectl for the others. `check_ntp` stays for an
  ntpd's configuration. Containers, on their host's clock, are left
  alone. The reference desktop: systemd-timesyncd, synchronised.
- [x] **`check_updates`**, offline: security updates waiting (upd003f)
  from what the package manager has cached (apt's -security suites,
  dnf's security advisories, zypper's security patches; pacman and apk
  have no such data), or that they cannot be counted (upd004i); whether
  they are installed automatically (upd002w: unattended-upgrades, Linux
  Mint's update automation, dnf-automatic with apply_updates); and a
  reboot pending (upd001w: /run/reboot-required, the running kernel's
  modules gone, a newer kernel-core installed). The reference desktop: 12 security
  updates waiting, none installed automatically.
- [x] **`check_sudo`**, from `cvtsudoers -e` (includes followed, aliases
  expanded): NOPASSWD for every command (sudo001w), for named commands
  (sudo002i, one list), `!authenticate` (sudo003w), wildcards in
  commands (sudo004w), sudoers files not root's alone (sudo005w).
  **`check_pam`**: no password quality module (pam001w), a minimum
  length under 8 (pam002w), no lockout after failed logins (pam003w),
  over /etc/pam.d and openSUSE's /usr/lib/pam.d. The reference desktop: the maintainer's
  NOPASSWD, Mint's four NOPASSWD helpers, neither PAM module.
- [x] **`check_units`**, what check_crontabs does for cron, for the
  enabled systemd services and those their timers and sockets start
  (read with `systemctl cat`): the programs their Exec*= lines run, with
  every directory above, through pathmsg against their User= (sysd004,
  sysd005, with their letters), the unit files and drop-ins root's alone
  (sysd006f), and lists of units defined in /etc or /run (sysd007i) and
  of package units replaced or extended there (sysd008i). pathmsg now
  passes over a sticky directory above the path, such as /tmp, which
  lets nobody replace what is not theirs; that changes check_crontabs'
  and check_aliases' findings the same way. The reference desktop: Wegweiser, the three backup
  units and two others local, nothing writable.
- [x] **`check_storage`**: /tmp, /dev/shm and a separate /var/tmp without
  nosuid or nodev (stor001w) or noexec (stor002i), /tmp not a file
  system of its own (stor003i); local file systems not on dm-crypt,
  looked for through the device stack (LVM on LUKS), a WARN on a
  machine with a battery of its own (stor004w) and an INFO elsewhere
  (stor005i); swap unencrypted under an encrypted root (stor006w); core
  dumps written as files with no limit (stor007w); USB storage when
  Tiger_Storage_NoUSB=Y says there should be none (stor008w). The reference desktop:
  /tmp on /, /dev/shm without noexec, nothing encrypted (its only
  battery is the mouse's).
- [x] **`check_containers`**: the Docker or Podman socket usable by
  anyone (cont002f) or by a group, whose members are named (cont001w);
  the Docker API on TCP without TLS (cont003f); dockerd running as root
  (cont009i); and each running container, from one inspect line: run
  privileged or given SYS_ADMIN (cont004w), the host's PID namespace
  (cont005w) or network (cont006i), the engine's socket mounted
  (cont007w), the host's / or /etc mounted writable (cont008w). A new
  category, containers. The reference desktop: the maintainer in the docker group, dockerd as
  root, Immich's four containers clean.
- [x] **Setuid and setgid against the package database**: fsys004a and
  fsys011a now compare with what the installed packages ship setuid or
  setgid (`util/pkgspecial`: rpm's file modes, pacman's mtree files,
  apk's installed database), where Tigris's static per-platform list
  was all there was; dpkg, which records no modes, keeps the list. The
  detail says which was used. `util/pkgspecial` agreed exactly with
  `find -perm` in Fedora (9 setuid), Arch (12 setuid, 3 setgid) and
  Alpine with sudo and shadow added (7, 1).
- [x] **Profiles as overlays**: `tigris --profile NAME` (or `-p`) reads
  `profiles/NAME` after the tigerrc, beside it first, then Tigris's own,
  so a profile holds only what differs: `quick` (no filesystem scan, the
  same as `tigerrc-quick`, which stays), `server` (USB storage
  forbidden, every account's PATH, processes using deleted files),
  `desktop` (no checks for server-only services), `container` (none of
  the host's kernel, boot, firewall, systemd or disks). An unknown
  profile stops the run (con013e). The run record names the profile,
  and tigris-diff counts it as part of the configuration.
- [x] **Checks that need root are skipped, not guessed.** Run as an
  ordinary user, a quick run on the reference desktop gave false findings (grpck could
  not open /etc/gshadow, GRUB's configuration unreadable, dpkg files
  reported missing), lost real ones (sshd -T, the listening processes
  of others, the firewall) or errors. Twelve checks now say `# Tigris:
  needs root` in their header, and without root each is skipped: a
  `# Skipped NAME` line in the report, a `skip` record in the JSON,
  `skipped` in the summary, and an exit status of at least 2. tigris-diff
  leaves a check skipped in either run out of both sides
  (`skipped_checks`), so comparing a root run with a user run does not
  call its findings resolved.
- [x] **The listening check reads /proc when nothing else will do.** On
  an Alpine without iproute2 the only lsof and netstat are busybox's,
  which ignore the options used, so check_listeningprocs reported
  nothing and said nothing. busybox's tools now count as missing, and
  the last resort is the kernel's own tables (/proc/net/tcp, tcp6, udp,
  udp6) with the processes found through their fd links; in an Alpine
  container it now reports a busybox nc on port 2222. On the reference desktop, as root,
  /proc and ss give the same 12 findings. Tiger_Listening_Source=proc
  forces it.

## 3.2.x: maintenance

- [x] Replace `egrep`, `tempfile` and `which`.
- [x] CI on GitHub Actions.
- [x] ShellCheck over `scripts/` and `systems/Linux/`, blocking at the
  error level. Tiger's `[ $TESTEXEC file ]` idiom, where the test
  operator is a variable, stopped ShellCheck parsing 11 files at the
  first use; written as `test $TESTEXEC file` (31 places, the same
  test), they parse, and the analysis found four real bugs: comment
  lines in the `ndd` table were never skipped (`[ $dev = \#* ]` cannot
  glob), a `((` that bash and ksh read as arithmetic, and two
  `2>&1 >/dev/null` that sent `grep` and `tty` errors into the report.
  The Perl `check_network` is left out by its shebang. The warning
  level is reviewed (`set X`, `> file` and `-a`/`-o` idioms, variables
  set by `config`) but not enforced.
- [x] `SECURITY.md`, issue templates and a contributing guide.
- [x] **Every finding id has an explanation, enforced.** The earlier
  count of 18 was a lower bound from a plain grep. The complete
  enumeration (literals, `pathmsg` arguments, the `file_access_list`
  and `signatures` data, `check_embed`'s suffix) found 25 gaps on
  master: 20 are now written, and five went away with the retired
  checks (tcpd's three, `xnet002f`, `bcm203x`). Two more entries cover
  new ids for placeholder findings the old grep could not see
  (`tig001e`, `pass022w`), and `apa003w` from the old list was never
  emitted by anything. `tests/explain_check.sh` fails CI on any id
  with no entry, and on any malformed id.
- [x] **Survive a dead network mount.** On 5 October the NAS mount was
  down (`df: /mnt/nas: Host is down`). The audit: the scan was already
  safe, it starts only from local filesystem types and stays on each
  with `-xdev`. What could hang was `lsof` in the deleted-files and
  listening-process checks, which stats every open file, and the
  account and PATH checks, which stat every home directory. `lsof` now
  runs with `-b` (no blocking kernel calls; the output the checks read
  is the same, and it is faster). Every home directory, and every mount
  point before the scan, is asked first with `df -P` under a kill
  timeout (`Tiger_Mount_Timeout`, 5 s, needs a `timeout` command); one
  that does not answer is reported (`acc025w`, `path010w`, `con011c`)
  and left alone, and homes under the same parent are not asked again.
  A symlink elsewhere whose target is under a dead mount can still
  stall the scan's dangling-link test; that needs the server back.
  `tests/mounts_check.sh` feeds a probe that hangs.
- [x] `tests/explain_check.sh` covers the id families built from data
  (`perm…`, `embed…`) but not a *new* id built from a variable: a
  mutation test confirmed `message WARN yyy$x"w"` passes unnoticed.
  Closed from the other side: the smoke test now checks that every id
  in a real run's JSON has an explanation (28 ids on the reference desktop).
- [x] Two runs in the same minute overwrite each other's report: the
  file names carried the time only to the minute. They now carry
  seconds (`security.report.HOST.YYMMDD-HH:MM:SS`); the byte sort in
  `tigris-diff` still orders a mix of old and new names by time, and
  `tigercron` was never affected (it rotates numbered `.1`/`.2` files).
- [x] `tigerrc-quick` is a full copy of `tigerrc` with one line changed,
  because an unset `Tiger_Check_*` means "run". Until profiles can be
  short overlays, `tests/profile_check.sh` fails unless the two differ
  only in that line.
- [x] The legacy variants `tigerrc-all` and `tigerrc-dist` carried
  the switches of the retired checks; dropped, since nothing installs,
  reads or documents them (the only generator was the dead manual
  `make distribution` target, whose recipe went with them).

## 3.3: modern Linux baseline

What the system looks like in 2026, not 2003. **3.3.0 was released on
7 October 2026** with its gate met: profiles (at least `quick`), the
dead-service checks retired, every id explained and tested, `SECURITY.md`.
**3.4.0 was released on 7 October 2026** with every item below; it is
3.4.0, not 3.3.1, because the exit status from the worst finding changes
what scripts and cron see.

**Clear out the old**
- [x] Other Unixes to the attic.
- [x] Retire the checks for things that are gone from a current Linux:
  inetd, xinetd and tcpd, rhosts and `.netrc`, anonymous FTP and
  ftpusers, printcap, OmniBack, NIS+, inittab and the static Debian
  advisory list from the early 2000s. Two corrections to the plan:
  tcpd went with inetd (it cannot run without it, and FAILs noise on
  any system without tcpwrappers), and the "LILO" check stayed because
  it is the GRUB 2 boot check.

**Profiles** (also the answer to "lean")
- [x] `quick`: leaves the filesystem scan out. 62 s on the reference desktop, where the
  full run takes about three minutes on a busy disk.
- [x] `server`, `desktop` and `container`, each a short tigerrc selecting
  the checks and the prune list that make sense for that kind of machine
  (`--profile NAME`, files in `profiles/`; in 3.4.0).
- [x] A non-root mode that reports "skipped: needs root" for the checks
  that need it, instead of guessing (in 3.4.0).

**Package integrity**
- [x] rpm, apk and pacman alongside dpkg.
- [x] Setuid and setgid files compared with what the package manager says
  should be setuid, not only with Tigris's own lists. rpm, apk and
  pacman only: dpkg records no modes (below). (`util/pkgspecial`, used
  by check_suid and check_sgid; in 3.4.0.)
- [x] dpkg: the entries of `dpkg-statoverride --list`, the one place
  dpkg records a mode and owner, compared with the files themselves
  (`deb_statoverride`, lin039w; in 3.4.0).
- `lin038w` for dpkg: **not possible, dropped** (decided 7 October
  2026). dpkg records no mode or owner for the files it installs:
  `dpkg --verify` checks md5 sums only, and the database holds file
  lists and sums. `lin038w` stays rpm, apk and pacman only, and its
  explanation says so. Reading modes from cached `.deb` files was
  rejected: the cache is often cleaned, and a `dpkg-deb -c` per package
  is slow.

**New checks**
- [x] SSH from `sshd -T`.
- [x] systemd unit hardening of network-facing services.
- [x] Kernel and file-system sysctl hardening; CPU vulnerability status.
- [x] sudo and `sudoers.d`, PAM (password quality, `faillock`), and
  accounts without passwords (`check_sudo`, sudo001w to sudo006e;
  `check_pam`, pam001w to pam003w; empty passwords were already
  pass011f; in 3.4.0).
- [x] systemd: enabled services and timers next to cron (`check_units`,
  sysd004 to sysd008i; in 3.4.0).
- [x] Firewall: incoming traffic denied by default, for IPv4 and IPv6,
  whatever wrote the rules (`check_firewall`, fire001w to fire004e; on
  master since 3.3.0).
- [x] Ports Docker publishes, which bypass the input chain (fire005w,
  fire006i; in 3.4.0).
- [x] Kernel lockdown and Secure Boot (`check_secureboot`, boot009w to
  boot013e and lin040w; in 3.4.0).
- [x] AppArmor or SELinux enforcing, auditd, journald persistence
  (`check_mac`, mac001w to mac004e; `check_audit`, aud001w to aud004e
  and logf008w; in 3.4.0).
- [x] Time sync (chrony, timesyncd) beside the NTP-only check
  (`check_timesync`, time001w to time004w; in 3.4.0).
- [x] Updates: automatic security updates configured, pending security
  updates, reboot required (`check_updates`, upd001w to upd004i; on
  master since 3.3.0). `check_patches`, apt-only, networked and off by
  default, stays as it was.
- [x] Storage: LUKS, mount options (`/tmp`, `/dev/shm`), core dumps, USB
  storage (`check_storage`, stor001w to stor008w; in 3.4.0).
- [x] Containers: Docker or Podman socket permissions, rootless mode,
  privileged containers (`check_containers`, cont001w to cont010e, and
  a 15th category, containers; in 3.4.0).

## 4.0: where Tigris beats Lynis

- [x] **A report other tools can rely on.** JSON Lines, a schema
  version, a JSON Schema, a documented contract, an exit status from the
  worst finding (0, 2 ERROR, 3 WARN, 4 FAIL, 5 ALERT; 1 did not run), and
  `--since` for a diff-aware run of the main command.
- [x] **One metadata file per finding id** (`meta/ID`, format in
  `doc/metadata.md`): severity, category, the checks that report it,
  references, the explanation; every id has `References` and every one
  that asks for action has a one-line `Fix` (since October 2026), and
  `Controls` carries the compliance mapping. `tigris explain ID`, the `category` of each JSON finding
  and the HTML reference are read from it, and
  `tests/explain_check.sh` holds the files and the code to each other
  both ways. On master since 3.3.0.
- [x] **Open compliance mapping** (after 3.5.0), free: CIS Controls v8, ISO 27001:2022
  Annex A, NIST 800-53 and UK Cyber Essentials, kept as data files and
  carried in the JSON. Lynis offers this only in its paid edition.
- [x] **Drift**: `tigris-diff` and `tigris-accept`, and the main
  command takes `--since RUN` (a report, or `last`) and prints only what
  changed, so cron needs no wrapper: `tigris -q --since last`.
- [x] **Offline audit** (3.5.0): `tigris --root /mnt/image` audits a mounted disk,
  a container image's root filesystem or a VM snapshot without booting
  it. Lynis cannot do this. On master: the option, links resolved inside
  the root (`util/rootpath`), the host's package tools pointed at the
  root's databases, skip records saying "live system" or "not offline
  yet", and the checks that read an offline root: package integrity on
  dpkg, rpm, apk and pacman; updates waiting; PAM; dpkg's overrides;
  sshd's configuration, worked out from its files as sshd would (the
  same findings as `sshd -T` on five distributions); sudo's rules, its
  includes read inside the root; accounts and passwords, owners named by
  the root's own passwd; cron; systemd units (`systemd-analyze --root
  cat-config`); the kernel and network settings it applies at boot.
  mount options and encryption from fstab and crypttab; the file system
  scan, ownership judged by the root's passwd and group. A container
  image (`docker run -v ROOTFS:/target:ro tigris --root /target`)
  carries every distribution's package tools for it.
- [x] **Offline audit, the rest** (3.7.0): the 16 of TIGER's original
  checks that could not read a root in 3.6.0 (permissions, devices and
  log files, umask and the rc umask, the boot loader and single-user
  mode, services and aliases, NFS exports, the release, the places
  intruders use, embedded paths, accounts that never logged in) read it
  now, so an image reads as fully as a running system; check_ntp and
  check_rootkit have no honest offline form and say "live system". On
  an image with systemd and sshd, ten checks are skipped as needing
  the running system (auditd, containers, the firewall, listening
  ports, AppArmor or SELinux, NTP, rootkits, Secure Boot, systemd's
  sandboxing and time synchronisation) and none as "not offline yet".
- [x] **A transparent summary** (3.6.0): counts by severity and category,
  and the score shows its formula, in the text report and the JSON
  summary alike (`util/summary`).
- [x] **Server-side Lynis gaps** (3.6.0): nginx and TLS, databases
  (MySQL/MariaDB, PostgreSQL, Redis), DNS resolvers, remote logging,
  certificate expiry. Static configuration analysis, offline-capable;
  no credentials, no live probing.
- [ ] **Rename the internals** in one release, with shims for old
  configurations: `tigerrc` to `tigris.conf`, `Tiger_*` to `Tigris_*`,
  `/etc/tiger` to `/etc/tigris`, `tigexp` to `tigris explain` (which
  already exists; `tigexp` is what it runs).
- [ ] A JSON schema 2 only if something has to be removed or renamed.

## Parity with Lynis

Full functional parity, tracked group by group in
`doc/parity-matrix.md` against Lynis 3.1.8-dev (43 test groups, 477
real tests): 6 groups covered, 10 strong with minor gaps, 15 partial,
10 gap, 2 not applicable. New checks follow the standing rules:
written from the upstream documentation of the thing being checked,
each with a metadata file per finding id and a fixture suite, offline
capable where honesty allows.

**Phase A: Linux parity** (done 2026-10-09, released in 3.7.0's
tree; KDC server-side, DB2, Qmail/OpenSMTPD and FileVault-on-Linux
recorded as out of scope).
- [x] New checks: Kerberos, LDAP, PHP, SNMP, Squid, CUPS printing,
  IDS/IPS presence, compilers and their permissions.
- [x] Second phases: databases (MongoDB auth, Oracle; DB2 not
  coverable offline), mail (Exim, Postfix, Dovecot depth), MAC
  frameworks (TOMOYO, grsecurity/PaX), crypto (entropy and RNG),
  file integrity (per-tool presence and config), filesystems (LVM
  detail, ACL support, locate db).
- [x] Verify-marked items: GRUB password, firewall logging,
  promiscuous interfaces, hosts duplicates, `at` jobs, console TTYs,
  rpcinfo and NFS daemon status, unpurged packages, YUM GPG signing,
  Docker file-permission depth, prelink handling (decided, no check).
- [x] Trivial folds: FireWire disable into check_storage, guest
  detection as informational.

**Phase B: macOS.** Done 2026-10-09, released in 3.8.0 (strategy in
`doc/macos-strategy.md`; check_sip, check_filevault, check_doas,
check_software, check_launchd, sudo symlink, passwd/group/firewall/
audit/logfiles/crontabs shadows, dispatch aggregator; differentiator
kept: Tiger-native fixture doctrine, no macOS runner needed for
unit confidence).
- [x] CI runner and fixture strategy, then SIP status, FileVault,
  doas, macOS package and App inventory, and the macOS side of
  every portable group.

**Phase C: BSDs.** Done 2026-10-09, released in 3.8.0 (strategy in
`doc/bsd-strategy.md`; FreeBSD first: gethostinfo recognition, one
voice for the pf and ipfw firewalls, newsyslog logfiles, package
auditing, accounting, inetd, dispatch aggregator; differentiator
kept: the same fixture doctrine as Linux, clean-room throughout).

**Phase D: Solaris and AIX.** Only with a maintainer and a CI runner
each, per the attic rule; until then their groups stay explicitly
uncovered rather than silently missing.

Lynis Enterprise paid surface (central management, scheduling) is out
of scope until decided; the command-line audit is the parity target.
The deliberate exceptions in `doc/parity-matrix.md` (no live
probing, retired legacy, no copied code) stand over parity work.

## Ideas parked for later

Not commitments. Written down so they are not lost.

- **Scan identities**: a name for a kind of scan (`--identity nightly`,
  `--identity pre-deploy`) carried in the run record, so a consumer can
  keep the series apart and `tigris-diff` compares like with like.
- **Notification**: a webhook that receives the summary, or the diff,
  when a run ends. Off unless configured, in keeping with offline by
  default.
- **More output formats** generated from the JSON rather than written
  into the checks: SARIF (for code-scanning dashboards), XML, CSV.
- **Wegweiser**: the Linux agent runs Tigris on each endpoint next to
  Lynis and ships the JSON; the schema and the `accepted` block are
  designed for that. First real consumer of the contract.
- **A fast path for large data disks**: let the scan skip filesystems by
  type or mount point from the profile, not just by directory.

## Windows (after 4.0)

Windows has nothing like Lynis or TIGER in the open: HardeningKitty checks
settings against CIS and Microsoft baselines, and the rest is commercial.
Tigris's shell code cannot run on a Windows host, but after 4.0 the parts
that matter are language-neutral: the finding ids and metadata, the JSON
schema, the compliance mapping and the explanations. A `tigris.ps1`
engine implements the same spec in PowerShell, using WMI and CIM, the
registry, the event log, `Get-Hotfix`, `auditpol`, `secedit` and
Defender's APIs, and emits the same JSON: one report format, one set of
ids, one `tigris explain`, two engines. It starts once the 4.0 schema is
stable, so it is built against a fixed contract.

## Engineering, ongoing

- **Tests:** plain `sh` fixtures with no framework. Checks that read
  `/proc`, `sshd -T`, `ss` or `systemd-analyze` take the command or the
  tree as a setting (`Tiger_Sysctl_Root`, `Tiger_SSHD_Cmd`,
  `Tiger_SS_Cmd`), so a test can feed them a fixture. Checks that depend
  on a package manager run in a real container: each plants a modified
  file, a deleted one, a changed mode and a stray, and requires exactly
  those four new findings on top of the image's own baseline. Test
  awk-dependent code under mawk, gawk and busybox awk.
  `tests/local-ci.sh` runs what CI runs, before pushing.
- **Safety:** no `eval` of data read from the system, `mktemp` for every
  temporary file, everything quoted. Files such as `/etc/os-release` and
  `/etc/pacman.conf` are read as text, never sourced. Tigris runs as
  root, so its own code has to be beyond reproach.
- **Speed and memory:** independent checks run in parallel. The two
  biggest wins so far were `util/flogit` (an `ls | awk` per file) and
  `deb_checkmd5sums` (a `dpkg -S` per diversion at 130 MB each). The
  next is the profiles above.
- **Packaging:** `.deb`, `.rpm` and apk built in CI and attached to
  every release from 3.7.0 (done), under the name `tigris` and
  separate from Debian's `tiger`; a COPR (done: `creativeheadz/tigris`,
  Fedora 43/44 and EPEL 9/10); a container image that scans a host or
  an image (done); an AUR package (`packaging/PKGBUILD`, published
  once the AUR registers new accounts again: it had stopped doing so
  in October 2026). Debian packaging of the fork is for later and
  would be its own package.
- **Docs:** man pages (done), `doc/json-format.md` (done), and a website
  (done, October 2026: https://creativeheadz.github.io/tigris/, built by
  `util/mksite` with sh and awk from the README, the docs and `meta/`, a
  page per finding id and per compliance framework, published with every
  release by `.github/workflows/pages.yml`; `tests/site_check.sh` follows
  every link).

## Not planned

- A GUI or a resident daemon. Tigris stays a command-line tool;
  dashboards belong to whatever reads its JSON.
- Automatic remediation. Tigris shows the fix and the administrator runs
  it.
- Copying code from other auditors.
- Central management of fleets (the paid Lynis Enterprise surface).
  Parity targets the command-line audit; this stays out until decided.
