#!/bin/sh
#
# tests/local-ci.sh - what CI runs, here before pushing
#
#   sh tests/local-ci.sh [lint] [build] [docker] [packages] [smoke]
#
# No arguments runs lint, build, docker and packages; smoke (the full
# run as root, minutes long) only runs when asked for. A section whose
# tools are missing
# here (no docker, no C toolchain, no shellcheck, no sudo) says SKIP and
# does not fail; everything that can run must pass. Exits 1 when anything
# failed.
#
# This mirrors .github/workflows/ci.yml step for step; when that file
# gains a job, this one should gain it too. It is also the shape an own
# CI pipeline would run, on Gitea Actions or anywhere else: plain sh,
# docker where a job needs another distribution, nothing GitHub-only.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
cd "$TIGER" || exit 1

# The run must leave the tree exactly as it found it; anything it builds
# happens in copies and temp dirs, never here.
# the tree copies the tests make carry this checkout's modes: a tigerrc
# or profile that group may write is (rightly) ignored, so make them 644
umask 022
treestart=`git status --short 2>/dev/null`
fail=0
want="$*"
[ -n "$want" ] || want="lint build docker packages"
run_section()
{
  case " $want " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}
say() { printf '%s\n' "$1"; }

# --- lint: syntax, every suite, ShellCheck (CI's lint job) ---

if run_section lint; then
  say "== lint: sh -n on every shell script"
  lintfail=0; n=0
  for f in $(git ls-files tiger tigris-diff tigris-accept tigexp tigercron config initdefs scripts systems util tests packaging); do
    case "$f" in tests/fixtures/*|*.c|*.pl|*.txt|*.lst|*.tmpl|*.xref|*README*|*/services|*/inetd|*_list|*signatures*|*advisories*|*baseline*|*embedlist*|*facl*|*.spec|*PKGBUILD*) continue;; esac
    [ -f "$f" ] || continue
    head -1 "$f" | grep -q 'perl' && continue
    n=$((n+1))
    sh -n "$f" || { echo "sh -n failed: $f"; lintfail=1; }
  done
  echo "$n scripts checked"
  [ "$lintfail" = 0 ] || fail=1

  say "== lint: every fixture suite"
  sh tests/all.sh || fail=1

  say "== lint: JSON schema"
  sh tests/schema_check.sh || fail=1

  if sudo -n true 2>/dev/null; then
    say "== lint: as root too (offline accounts, cron, offline scan, hostile root)"
    sudo sh tests/offline_accounts_check.sh || fail=1
    sudo sh tests/cron_check.sh || fail=1
    sudo sh tests/offline_scan_check.sh || fail=1
    sudo sh tests/hostile_root_check.sh || fail=1
  else
    say "SKIP: no passwordless sudo, the as-root suites only run on CI"
  fi

  if command -v shellcheck >/dev/null 2>&1; then
    say "== lint: ShellCheck (errors)"
    files=
    for f in tiger tigexp tigercron config initdefs util/realpath util/rootpath util/summary tests/*.sh packaging/*.sh \
        $(git ls-files scripts systems/Linux/2 systems/MacOSX/default systems/FreeBSD/default systems/default | grep -v '\.pl$\|README\|\.lst$\|\.tmpl$\|_list$\|signatures\|advisories\|baseline\|embedlist\|facl\|/services$\|/inetd$\|\.sh$'); do
      head -1 "$f" | grep -q perl && continue
      files="$files $f"
    done
    # shellcheck disable=SC2086
    shellcheck -s sh -S error $files || fail=1
  else
    say "SKIP: shellcheck is not installed"
  fi
fi

# --- build: C helpers, docs, install (CI's build job) ---

if run_section build; then
  if command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1; then
    # A test runner must not dirty the tree it tests: CI builds on a fresh
    # checkout per job, and the packages section bind-mounts this tree, so
    # host-built binaries leaking into it break the container builds (an
    # Alpine abuild fails outright on a glibc-linked helper). Build a copy.
    B=`mktemp -d`
    ( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$B" && tar -xf - )
    cd "$B" || exit 1
    say "== build: configure and make"
    ./configure && make || fail=1
    say "== build: the helpers install into bin/"
    make -C c install && ls -l bin/ && test -x bin/snefru && test ! -e bin/realpath || fail=1
    say "== build: findings reference built from meta/"
    grep -c '<dt id=' doc/explanations.html || fail=1
    say "== build: make install into a staging directory, man pages included"
    W=`mktemp -d`
    make install DESTDIR="$W/dest" || fail=1
    for m in tiger tigexp tigercron tigris tigris-diff tigris-accept; do
      test -f "$W/dest/usr/local/share/man/man8/$m.8" || { echo "no $m.8"; fail=1; }
    done
    rm -rf "$W"
    cd "$TIGER" || exit 1
    rm -rf "$B"
  else
    say "SKIP: no C compiler, the build only runs on CI"
  fi
fi

# --- docker: the distribution jobs (CI's awks, debian, package, container jobs) ---

if run_section docker; then
  if command -v docker >/dev/null 2>&1; then
    say "== docker: every suite under mawk, gawk and busybox awk"
    docker run --rm -v "$PWD:/tiger:ro" debian:stable sh -c 'apt-get update -qq >/dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq binutils file procps diffutils bsdextrautils sudo python3-jsonschema >/dev/null 2>&1; sh /tiger/tests/all.sh' || fail=1
    docker run --rm -v "$PWD:/tiger:ro" archlinux:latest sh -c 'pacman -Sy --noconfirm -q inetutils binutils file diffutils procps-ng sudo python-jsonschema >/dev/null 2>&1; sh /tiger/tests/all.sh' || fail=1
    docker run --rm -v "$PWD:/tiger:ro" alpine:latest sh -c 'apk add -q coreutils binutils file diffutils procps sudo py3-jsonschema >/dev/null 2>&1; sh /tiger/tests/all.sh' || fail=1

    say "== docker: Debian checks"
    for img in debian:stable debian:sid ubuntu:24.04; do
      echo "-- $img"
      docker run --rm -v "$PWD:/tiger:ro" "$img" sh /tiger/tests/deb_checks.sh || fail=1
    done

    say "== docker: package integrity"
    for img in fedora:latest rockylinux:9 alpine:latest archlinux:latest; do
      echo "-- $img"
      docker run --rm -v "$PWD:/tiger:ro" "$img" sh /tiger/tests/pkg_checks.sh || fail=1
    done
    echo "-- opensuse/tumbleweed:latest"
    docker run --rm -v "$PWD:/tiger:ro" opensuse/tumbleweed:latest sh -c 'zypper -q install -y gawk tar findutils; sh /tiger/tests/pkg_checks.sh' || fail=1

    say "== docker: container image, auditing a root"
    docker build -t tigris:local . || fail=1
    W=`mktemp -d`
    mkdir -p "$W/root" "$W/reports"
    docker create --name tigris-local-root debian:stable >/dev/null
    if sudo -n true 2>/dev/null; then
      docker export tigris-local-root | sudo tar -C "$W/root" -xf -
    else
      docker export tigris-local-root | tar -C "$W/root" -xf -
    fi || fail=1
    docker rm tigris-local-root >/dev/null
    docker run --rm -v "$W/root:/target:ro" -v "$W/reports:/opt/tigris/log" tigris:local -q --root /target
    st=$?
    echo "exit status $st"
    case $st in 0|3|4|5) ;; *) echo "the audit did not finish"; fail=1 ;; esac
    j=$(ls "$W"/reports/*.jsonl 2>/dev/null | head -1)
    if [ -n "$j" ]; then
      # The report is root's, as the audit ran as root
      if sudo -n true 2>/dev/null; then
        sudo grep -q '"type":"run".*"root":"/target"' "$j" || { echo "no run record"; fail=1; }
        sudo grep -q '"type":"summary"' "$j" || { echo "no summary record"; fail=1; }
      else
        grep -q '"type":"run".*"root":"/target"' "$j" || { echo "no run record"; fail=1; }
        grep -q '"type":"summary"' "$j" || { echo "no summary record"; fail=1; }
      fi
    else
      echo "no JSON report written"; fail=1
    fi
    # The exported root is root's when sudo extracted it
    if sudo -n true 2>/dev/null; then sudo rm -rf "$W"; else rm -rf "$W"; fi
  else
    say "SKIP: docker is not installed, the distribution jobs only run on CI"
  fi
fi

# --- packages: every format builds, installs and runs (CI's packages job) ---

if run_section packages; then
  if command -v docker >/dev/null 2>&1; then
    W=`mktemp -d`
    for spec in "deb debian:stable" "rpm fedora:latest" "apk alpine:latest" "aur archlinux:latest"; do
      set -- $spec
      say "== packages: $1"
      mkdir -p "$W/$1"
      docker run --rm -v "$PWD:/tiger:ro" -v "$W/$1:/out" "$2" sh /tiger/packaging/ci.sh "$1" /out || fail=1
    done
    rm -rf "$W"
  else
    say "SKIP: docker is not installed, the packages only build on CI"
  fi
fi

# --- smoke: the full run as root (CI's smoke job), only when asked ---

if run_section smoke; then
  if sudo -n true 2>/dev/null; then
    say "== smoke: full run"
    sudo sh tests/smoke.sh || fail=1
  else
    say "SKIP: no passwordless sudo, the full run only happens on CI"
  fi
fi

treeend=`git status --short 2>/dev/null`
if [ "$treeend" != "$treestart" ]; then
  say "local-ci: FAIL: the run changed the tree (before/after git status):"
  printf '%s\n' "--- before" "$treestart" "--- after" "$treeend"
  fail=1
fi

[ "$fail" = 0 ] && say "local-ci: everything that ran passed" || say "local-ci: FAILURES above"
exit $fail
