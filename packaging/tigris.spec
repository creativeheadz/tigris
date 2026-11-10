%define _tag version_4_1_0
# No -debuginfo: five small helpers, and EL9's toolchain errors on their
# empty debugsource list.
%define debug_package %{nil}

Name:           tigris
Version:        4.1.0
Release:        1%{?dist}
Summary:        Security auditor for Linux, macOS and the BSDs, descended from TIGER
License:        GPL-2.0-or-later
URL:            https://github.com/creativeheadz/tigris
Source0:        https://github.com/creativeheadz/tigris/archive/refs/tags/%{_tag}.tar.gz
BuildRequires:  gcc
BuildRequires:  make

%description
Tigris audits a Linux system against 63 checks and explains every
finding, with JSON output, offline auditing of images that are not
running, and per-finding compliance controls. It installs under its
own name and paths.

%prep
%setup -q -n %{name}-%{_tag}

%build
./configure --prefix=%{_prefix} --sysconfdir=%{_sysconfdir} \
  --localstatedir=%{_localstatedir} \
  --with-tigerhome=%{_libdir}/tigris \
  --with-tigerconfig=%{_sysconfdir}/tigris \
  --with-tigerwork=%{_localstatedir}/lib/tigris \
  --with-tigerlog=%{_localstatedir}/log/tigris \
  --with-tigerbin=%{_sbindir}
make %{?_smp_mflags}

%install
make install DESTDIR=%{buildroot}
sh packaging/stage.sh %{buildroot} %{_libdir}/tigris %{_sbindir}

%pre
# 3.x shipped tigerrc, 4.0 ships tigris.conf. Upgrading, rpm saves an
# edited tigerrc as tigerrc.rpmsave and the new default would run in its
# place: note that this is such an upgrade, so %posttrans can make the
# admin's file the tigris.conf.
if [ "$1" -ge 2 ] && [ -e %{_sysconfdir}/tigris/tigerrc ]; then
  touch %{_localstatedir}/lib/tigris/.tigerrc-upgrade 2>/dev/null || :
fi

%posttrans
m=%{_localstatedir}/lib/tigris/.tigerrc-upgrade
if [ -e "$m" ]; then
  rm -f "$m"
  c=%{_sysconfdir}/tigris
  if [ -f "$c/tigerrc.rpmsave" ] && [ ! -e "$c/tigerrc" ]; then
    [ -e "$c/tigris.conf" ] && mv -f "$c/tigris.conf" "$c/tigris.conf.rpmnew"
    mv -f "$c/tigerrc.rpmsave" "$c/tigris.conf"
    echo "tigris: your edited tigerrc is now $c/tigris.conf; the new default is tigris.conf.rpmnew"
  fi
fi

%files
%license COPYING
%config(noreplace) %{_sysconfdir}/tigris/
%{_sbindir}/tigris
%{_sbindir}/tigris-diff
%{_sbindir}/tigris-export
%{_sbindir}/tigris-accept
%{_libdir}/tigris/
%dir %{_localstatedir}/lib/tigris
%dir %{_localstatedir}/log/tigris
%{_mandir}/man8/tigris.8*
%{_mandir}/man8/tigris-diff.8*
%{_mandir}/man8/tigris-export.8*
%{_mandir}/man8/tigris-accept.8*

%changelog
* Tue Nov 10 2026 Andrei Trimbitas <a.trimbitas@oldforge.tech> - 4.1.0-1
- Tigris 4.1.0: Lynis test-level parity rounds 1-4; SARIF/CSV export,
  scan identities, the filesystem fast path; signed release artefacts.

* Thu Oct 22 2026 Andrei Trimbitas <a.trimbitas@oldforge.tech> - 4.0.0-1
- Tigris 4.0.0: its own names (tigris.conf, Tigris_*), the old ones
  still read, an edited tigerrc carried over; nine checks deeper;
  package sources that stopped publishing.

* Fri Oct 16 2026 Andrei Trimbitas <a.trimbitas@oldforge.tech> - 3.9.0-1
- Tigris 3.9.0: the hostile-image fix completed and hardened; setuid
  judged file by file; releases against end of support; a summary.

* Sat Oct 10 2026 Andrei Trimbitas <a.trimbitas@oldforge.tech> - 3.8.1-1
- Tigris 3.8.1: security fix, nothing read from an audited image runs as
  code; a fix and references for every finding; ten bug fixes.

* Fri Oct 09 2026 Andrei Trimbitas <a.trimbitas@oldforge.tech> - 3.8.0-1
- Tigris 3.8.0: macOS and FreeBSD checks, busybox-awk hardening.

* Fri Oct 09 2026 Andrei Trimbitas <a.trimbitas@oldforge.tech> - 3.7.0-1
- Tigris 3.7.0: the offline audit complete, packages, a spinner.

* Thu Oct 08 2026 Andrei Trimbitas <a.trimbitas@oldforge.tech> - 3.6.0-1
- First package of the fork, co-installable beside tiger.
