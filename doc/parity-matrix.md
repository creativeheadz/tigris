# Lynis parity matrix

Where Tigris stands against Lynis, group by group, so the roadmap's
parity target is a checklist instead of a slogan. Lynis is reference
only: no Lynis code is copied here or into the checks (GPL-3.0;
Tigris stays GPL-2.0-or-later). Statuses: covered, strong (minor
gaps), partial, gap, N/A (template or platform-only).

Inventoried from Lynis 3.1.8-dev (`include/tests_*`, 43 files, 480
registrations, 477 real tests) against Tigris on master. Lynis
master has not moved since 2026-09-16, before the 23-Oct-2026
inventory, so both recounts read the same upstream tree: every one
of the 43 per-file registration counts matches. Recounted test by
test 2026-11-10 after the roadmap's rounds 1-4; the rows name the
new finding ids, the Counts section the new verdicts. Refresh by
re-running the inventory and updating the counts below.

## Covered (27 groups)

| Lynis group | Tests | Tigris cover |
|---|---|---|
| banners | 5 | check_issue (unchanged: off by default, site template; see overstatements) |
| dns | 1 | check_dns |
| file_permissions | 1 | check_perms (the Lynis profile files it names fully, incl. both grub.cfg paths and user.cfg since round 1; the rest for write bits; Linux only) |
| homedirs | 6 | check_accounts (acc026w/027w/028w: 750 or stricter, the account's own by uid, a plain history file), check_path |
| kernel_hardening | 1 | check_sysctl (31 of the 44 Linux keys exact: sysrq as a mask, loose rp_filter, proxy ARP, multicast routing, ctrl-alt-del, tcp_timestamps, bpf_jit_harden, ldisc_autoload; sysrq and source-route effectiveness differ from the profile on kernel-doc grounds), check_sysctl on FreeBSD/macOS (sctl001w-006w: 8 keys, 3 of the profile's) |
| ssh | 5 | check_ssh (sshd -T; 18 of 20 options: forwarding, tunnels, client-alive probes, StrictModes, MaxSessions, DEBUG logging, UseDNS, PrintLastLog, FingerprintHash added; Port and TCPKeepAlive deliberately not judged) |
| filesystems | 23 | fstab/crypttab, mount options (stor001w/002i/003i and stor017w/018i/019i: every Lynis mount judged, 25 of 26 flags; /boot noexec deliberate; /home, /var and /tmp separateness), the sticky bit (fsys008f), scan, check_storage (stor011i LVM, stor012w ACLs, stor013w locate db incl. plocate, each against its own group) |
| time | 17 | check_ntp, check_timesync (time005w/006w sources and falsetickers, stratum in time003i; OpenNTPD told apart and asked with ntpctl; FreeBSD ntpd/OpenNTPD/chronyd and macOS timed/sntp judged, time001w/002w/004w/005w/006w reused) |
| webservers | 18 | check_apache (apa007i/008w/009w/010w modules, proxy, Dav, status; apa012w TraceEnable, apa013w/014w/015w evasive, reqtimeout-or-qos, security), check_nginx (incl. ngx013w error_log debug), check_certs; remaining: 6710/6712/6714 partial (prefer-server-ciphers, add-HTTPS, missing-log-file edges) |
| crypto | 8 | check_crypto (cry001w/002w/003i), check_certs (expiry), check_storage (LUKS, swap), check_filevault |
| databases | 16 | check_databases (MySQL/MariaDB + dbs017f empty-root probe, PostgreSQL + dbs021w conf modes, Redis + dbs018w/019w/020i password/bind/CONFIG-rename, MongoDB dbs011f/012w/013w/014f, Oracle dbs015w/016w; DB2 not coverable offline); remaining: 1820 partial (--auth on the command line), 1828 partial (drop-in modes), 1882 partial (passwordless-conf modes) |
| file_integrity | 18 | check_integrity (int001w/002w/003i AIDE/AFICK; the database AIDE reads: database_in, macros, includes; empty counts as none; watcher inventory), aide/tripwire runners |
| mac_frameworks | 8 | check_mac (AppArmor, SELinux, TOMOYO mac007w/008i, PaX mac005w/006i) |
| mail_messaging | 11 | check_mail (mail001w/002w/003i + mail004w VRFY; Exim, Postfix, Dovecot, Qmail, OpenSMTPD); remaining: 8818 partial (OS-name banners missed), 8817 none (needs live postconf) |
| malware | 11 | check_antivirus (avir001w/002i ClamAV), check_rootkit, chkrootkit, rkhunter |
| storage_nfs | 8 | check_exports (an export to `*`, to no host, or with no client is an export to everyone; exports.d read), check_nfsd (nfs015w/016i) |
| usb | 3 | check_storage (USB storage, USBGuard stor014i/015w/016w, uas, authorized_default) |
| hardening | 4 | check_compilers (cmp001i/002w/003i) |
| kerberos | 6 | check_kerberos (krb001w/002i/003w, client side; KDC server-side out of scope) |
| ldap | 2 | check_ldap (ldap001w/002w) |
| php | 9 | check_php (php001w/002i/003i + php004w/005w/006i allow_url_fopen, enable_dl, disable_functions noted; all SAPIs; conf.d drop-ins read, effective value judged); remaining: 2376 partial (bare-php.ini edge), 2382 none (FPM listen; Display-only signal), 2368 exception (PHP 5.3 and older) |
| printers_spoolers | 9 | check_printers (print001w/002w/003w; printcap retired) |
| snmp | 3 | check_snmp (snmp001w/002i/003i) |
| squid | 11 | check_squid (squid001w/002w/003w + squid004w Safe_ports, squid005i version note, squid006w loose modes); remaining: 3630 none ([T]-marked reply_body_max_size) |
| storage | 1 | check_storage (stor010w FireWire) |
| tooling | 9 | check_ids (ids001w/002w/003i) |
| virtualization | 1 | check_release (osv003i guest detection) |

## Strong (14 groups, minor gaps)

| Lynis group | Tests | Tigris cover | Remaining |
|---|---|---|---|
| authentication | 36 | accounts, passwd, group, pam, sudo, neverlogin, umask; login.defs ageing on every distribution (pass023i/024w); DES, md5crypt, sha1crypt, sunmd5, nt, bsdicrypt and unknown hashes (pass013w); expired-yet-usable accounts (pass025w); the FreeBSD and macOS legs run (9204/9208/9222/9226 full, 9212/9218 full; 9283's FreeBSD leg proven, macOS moot, verdict unchanged) | DONE 2026-10-09: check_doas (dos001w/002i/003w; nopass rules, conf writable past root; macOS phase, BSD port later); DONE 2026-10-09: macOS check_passwd/check_group shadows (dscl/dslocal, pass001w/002w/014w/015w/017w + grp001w/002w reused; hashes and grpck cut); password hashing rounds (9229 partial, 9230 none); 9282/9284 none (no-expiry-set, locked-removal unjudged); LDAP-in-PAM (see ldap) |
| boot_services | 27 | check_lilo (GRUB 2 in /boot/grub and /boot/grub2, password only with superusers, user.cfg; LILO), check_single (every architecture; systemd rescue and emergency sulogin, sum002f/003w; inittab where SysV reads it), check_secureboot, systemd units | other bootloaders backlogged with Solaris |
| containers | 7 | check_containers (10 ids) | zones backlogged with Solaris; verify Docker file-permission depth |
| firewalls | 17 | check_firewall (nft/iptables/ufw/firewalld, Docker ports) | verify firewall logging; DONE 2026-10-09: macOS half (pf + application firewall, fire001w/002w reused; ipfw is long dead, no check); DONE 2026-10-09: FreeBSD half (pf status/rules + ipfw default-only, one voice, fire001w/002w reused; strict pf.conf consistency cut) |
| logging | 23 | check_logfiles (per-file rotation logf011w; a configured syslog daemon not running logf012w), check_remotelog (action() and destination drivers over lines, omrelp, syslog.conf @host), journald persistence | metalog, RFC 3195; syslog-ng -s consistency (2134 none); klogd and minilogd moot (dead daemons); wazuh-agent (see tooling; 2154 stays partial on it); DONE 2026-10-09: macOS half (log writability logf005f, readable trail logf009w new; absence not judged, unified era); DONE 2026-10-09: FreeBSD half (newsyslog managed/missing/writable/loose-mode, logf001f/005f reused + logf010w new; remote judgment cut) |
| networking | 16 | check_network, check_listeningprocs (ss/lsof/netstat//proc) | verify promiscuous-mode check; DONE 2026-10-09: FreeBSD half (ifconfig PROMISC, prom001w reused) |
| ports_packages | 43 | pkg_integrity (dpkg/rpm/apk/pacman), check_updates (upd010w: apt sources naming no security suite for the release), check_patches | verify unpurged packages, YUM GPG signing; DONE 2026-10-09: check_software (swd001w/002w; app and Cellar writability, auto-update prefs; macOS phase); DONE 2026-10-09: check_pkg (upd006w; pkg updating notices; FreeBSD phase; pkg audit/portaudit/portmaster cut as network/dead); DONE 2026-10-16: check_repos (upd007w/008w/009w; stale sources by newest suite, unrefreshed lists, expired Valid-Until; apt, dnf, zypper, pacman, apk; offline) |
| accounting | 17 | check_audit (auditd; installed/enabled judged offline; the audit log's keeping aud012w), check_accounting (aud005w/006i sysstat, aud007w/008i snoopy, aud009i/010w/011i process accounting) | Solaris daemons backlogged with Phase D; cmd tooling (9670/9672 none); DONE 2026-10-09: macOS half (audit_control flags, aud001w/002w reused; running-state is the watchdog's, unified log persists by default) |
| insecure_services | 21 | Linux check_inetd (telnet/rsh/TFTP servers installed inet006w or enabled inet005f, small internal services inet007w, super-servers inventoried inet008i) + FreeBSD inetd (inet001w) | DONE 2026-11-10: Linux servers, xinetd/inetd (round 2); xinetd talk/rsync INFO-only (8116 partial); tcp_wrappers none (dead upstream); clients deliberately not judged (see exceptions); NIS/NIS+ retired; macOS fingerd/ftp-proxy (8050 none) |
| kernel | 13 | check_sysctl, core dumps (stor007w file pattern gated on hard core 0; stor020i systemd-coredump keeping; 5820 full), pending-reboot | I/O scheduler and module detail (mostly informational) |
| memory_processes | 5 | check_runprocs, check_finddeleted | prelink handled (Oct 2026: no longer called for checksums, no longer shipped); zombie/heavy-IO are informational (not judged) |
| nameservices | 27 | check_dns (resolvers, unbound, BIND, PowerDNS dns008f) | verify hosts duplicates; NIS retired deliberately |
| scheduling | 5 | check_crontabs, check_cron (run on FreeBSD and macOS too; 7704 full) | at jobs: Lynis reports nothing on at (detection only); Tigris judges at-allow (cron011w); DONE 2026-10-09: macOS half (tabs, periodic, full pathnames; cron008f/008w/009w/001w reused; orphans and at-allow cut) |
| shells | 4 | login shells, umask in shell configs, idle killing (shl001i/002i TMOUT, autologout), FreeBSD console ttys (shl003w; SHLL-6202 full) | DONE 2026-11-10: console TTYs (round 4) |

## N/A (2 files)

| Lynis file | Tests | Note |
|---|---|---|
| custom.template | 3 | template for custom tests, not real coverage |
| system_integrity | 1 | DONE 2026-10-09: check_sip (sip001w; disabled or custom-off named; macOS phase) |

## Deliberate exceptions (parity does not override these)

- No live probing: NIS zone transfers and anything needing crafted
  packets stay out (read-only and offline by default).
- Retired legacy: NIS/NIS+, printcap, inetd-era services stay retired;
  their Lynis counterparts count as intentionally uncovered.
- No copied code: every port is written from the upstream documentation
  of the thing being checked.
- sshd: Port (obscurity) and TCPKeepAlive (its keepalives only drop
  dead connections) are not judged; neither CIS nor the man page
  wants them changed.
- sysctl: bootp_relay (ip-sysctl.rst: not implemented),
  kernel.core_uses_pid (names the core file) and
  kernel.modules_disabled (unusable where anything hot-plugs) stay
  unjudged; sysrq as a mask and source-route effectiveness differ
  from the profile on kernel-doc grounds, which flag every stock
  host if read literally.
- No judged clients: telnet, rsh and TFTP clients are not judged
  (Debian installs a telnet client everywhere; a client gives an
  attacker nothing nc lacks).
- Dead upstream paths: register_globals (PHP 5.3 and older),
  klogd and minilogd are not judged; neither is suhosin (PHP-2379,
  commented out upstream) nor any OpenBSD/NetBSD/DragonFly-only leg
  (outside FreeBSD, Tigris's BSD). Legacy GRUB passwords are
  judged, as Lynis judges them.
- macOS accounts without a ShadowHash are not called passwordless:
  they cannot authenticate at all, which is also disabled root's
  stock shape.

## Counts

Covered 27, strong 14, partial 0, gap 0, N/A 2: 43 files, 477
real tests, as counted by group. The grades above are coarse upper
bounds, kept for continuity; what follows is the test-level
recount, done 2026-11-10 on current master against the same Lynis
tree the 23-Oct-2026 inventory read (master at 2026-09-16; all 43
per-file registration counts match, so there is no Lynis drift).
Refresh by re-running the inventory and updating the counts below.

Of the 179 Lynis tests that report a weakness, Tigris now covers
86 fully, 45 in part and 52 not at all. The 23-Oct-2026 buckets
were 37/50/96; the four rounds moved 57 tests, +49 full, -5
partial, -44 none:

- Round 1, the checks that did not work (+16/-5/-11, 17 tests):
  AUTH-9229 N→P (weak and unknown hashes named); AUTH-9286,
  AUTH-9308, BOOT-5260, FINT-4316, STRG-1930, PKGS-7388,
  FILE-6362, FILE-6363 N→F (login.defs ageing, single-user
  sulogin, rescue.service, the AIDE database AIDE reads,
  exports to everyone, the missing security suite, the sticky
  bit); BOOT-5122 P→F (GRUB 2 in /boot/grub2, password with
  superusers); AUTH-9204, AUTH-9208, AUTH-9222, AUTH-9226,
  SCHD-7704 P→F and AUTH-9212, AUTH-9218 N→F (the portable
  checks run on FreeBSD and macOS instead of stopping at
  init001e). LOGG-2154 and STRG-1928 stayed put (P and F):
  the remotelog and exports.d fixes made them correct, and
  1928 now stricter than Lynis, without moving the verdict.
- Round 2, depth on the core (+16/-1/-15, 21 tests): SSH-7408,
  HOME-9304, INSE-8016, KRNL-5820, FILE-6374, FILE-6310 P→F;
  HOME-9306, HOME-9310, INSE-8000, INSE-8304, INSE-8322,
  INSE-8320, LOGG-2146, ACCT-9622, ACCT-9634, AUTH-9288 N→F;
  INSE-8006, INSE-8100, INSE-8106, INSE-8116, LOGG-2130 N→P
  (xinetd installed/configured and the syslog daemon's running
  state judged in part: talk/rsync INFO-only, the
  nothing-anywhere case silent). The rest of
  the round (sysrq as a mask, loose rp_filter, proxy ARP,
  multicast routing, coredump keeping) reads in the list
  items below. Two scope items were not done: uncommon
  protocols and filesystems left loadable (FILE-6430 stays
  none) and the SELinux config-vs-runtime mode mismatch (no
  Lynis test; Tigris-side).
- Round 3, services (+15/+2/-17, 17 tests): HTTP-6660,
  HTTP-6640, HTTP-6641, HTTP-6643, HTTP-6716, MAIL-8820,
  DBS-1816, DBS-1884, DBS-1886, DBS-1888, PHP-2320, PHP-2374,
  SQD-3613, SQD-3624, SQD-3680 N→F; DBS-1828, PHP-2376 N→P
  (pg drop-in modes; the bare-php.ini edge). PHP drop-ins
  made 2378 more correct without moving it (stays full).
- Round 4, FreeBSD and macOS (+2/-1/-1, 2 tests): SHLL-6202
  N→F (the console in /etc/ttys), TIME-3104 P→F (timekeeping
  on FreeBSD and macOS). AUTH-9283 stays full: the FreeBSD
  leg already judged pass011f (now proven by a fixture) and
  macOS has no passwordless state to judge (see exceptions).

Inside the list-walking tests: sshd options 18 of 20 (Port and
TCPKeepAlive deliberate); Linux sysctl keys 31 of 44 exact (34
judged: sysrq and two source-route keys differ on kernel-doc
grounds; 3 deliberate, 6 knobs dead on modern kernels, and
net.ipv6.conf.all.send_redirects the one true gap); mount
options 28 of 29 (25 of 26 flags across the 10 mounts, plus
/home, /var and /tmp separateness; /boot noexec deliberate);
permission files 10 of 30 (grub2 path and user.cfg newly judged
in round 1; the .rhosts row corrected, still covered). The four
named lists: 87 of 123 covered, from 43 (+13 sshd, +11 sysctl,
+18 mounts, +2 perms). New since October: FreeBSD/macOS sysctl
keys, 3 of
the profile's 33 judged (plus 5 FreeBSD keys outside the
profile); the rest await sysctl -a and stock-default evidence
from real FreeBSD and macOS systems (about two dozen on the
roadmap's 31-key scope; the profile itself carries 33).

Two notes on the old numbers. The published 23-Oct buckets sum
to 183 (37+50+96), not the 179 headline; the recount carries
the buckets forward by verified deltas and does not reallocate
the gap of 4, which lives in the carried rest. And the 213
list items were never itemised in the tree: the four named
lists sum here to 123 with 43 covered at baseline, leaving 1
of the published 44 in the unattributed remainder (~90
items, composition unverifiable), which is carried as
reported; the FreeBSD/macOS sysctl keys above are counted
separately in any case.

How a verdict was reached: each cited check body was opened,
current master, and each new finding id traced to the Lynis
test it answers; grep located, code decided. A test counts as
reporting when Lynis can answer it with a suggestion, a
warning, a non-green display, or docked hardening points
(the mount-options test sets the precedent). Per-OS legs
count where Tigris's check runs there: Linux-scoped service
checks are judged on Linux, portable checks on every
platform they run on, and a leg Lynis itself skips (preqs
failed) is moot. An INFO finding counts as covered where
Lynis's signal is advisory (the mail003i precedent).

Known overstatements still standing: banners (check_issue is
off by default and compares against a site template),
kerberos (the KDC side is scoped out, a decision, not an
exception), file_permissions (write bits for most, Linux
only). Fixed since October: homedirs, insecure_services on
Linux, kernel_hardening (20→31 of 44), ssh (5→18 of 20),
and `cmp003w`, which is `cmp003i` and now says so in its row.

Every finding that can show a gap maps to its compliance
controls, or is declared unmapped in doc/controls.map with a
reason, and tests/explain_check.sh enforces it. check_perms
checks every match of its wildcard entries, offline and live.
