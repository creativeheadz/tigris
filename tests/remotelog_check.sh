#!/bin/sh
#
# tests/remotelog_check.sh - check_remotelog against a root of its own
#
# A fake root with rsyslog forwarding over legacy @/@@ and omfwd (and a
# template whose "@" is not a target, and a stray file rsyslog will
# ignore), a syslog-ng tcp() destination reached through @include, and
# journal-upload with a URL. Then a root with local logging only, and
# one with no syslog at all: rlog002i either way. Tigris_Show_INFO_Msgs
# is on, since both verdicts are INFO.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
cp "$W/tigris.conf" "$W/tigris.conf.base"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
join() {
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--'
}

r="$W/root"
mkdir -p "$r/etc/rsyslog.d" "$r/etc/syslog-ng/conf.d" "$r/etc/systemd"
printf '$ModLoad imuxsock\n$IncludeConfig /etc/rsyslog.d/*.conf\n*.emerg @loghost.example\n*.* @@[2001:db8::1]:514\n$template precise,"%%timegenerated%% @notahost %%msg%%\\n"\n' > "$r/etc/rsyslog.conf"
printf '*.* action(type="omfwd" target="backup.example" port="601" protocol="tcp")\n' > "$r/etc/rsyslog.d/10-fwd.conf"
printf '*.* /var/log/local\n' > "$r/etc/rsyslog.d/20-local.conf"
echo "old rules, kept just in case" > "$r/etc/rsyslog.d/old"
printf '@version: 3.35\n@include "/etc/syslog-ng/conf.d/*.conf"\n' > "$r/etc/syslog-ng/syslog-ng.conf"
printf 'destination d_remote {\n  tcp("ng.example" port(514));\n};\nlog { source(s_src); destination(d_remote); };\n' > "$r/etc/syslog-ng/conf.d/remote.conf"
printf '[Upload]\nURL=https://logs.example:19532\n' > "$r/etc/systemd/journal-upload.conf"

cp "$W/tigris.conf.base" "$W/tigris.conf"
{ echo "Tigris_Sysctl_Root='$r'"; echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_remotelog ) 2>&1 | join > "$W/out"
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -F -c -- "$1" "$W/out"; }

has "[rlog001i] Logs are forwarded to https://logs.example:19532, @@[2001:db8::1]:514, @loghost.example, backup.example, ng.example (journal-upload and rsyslog and syslog-ng)." &&
  ok "rsyslog @/@@/omfwd, syslog-ng tcp() and journal-upload: rlog001i names them all" || { bad "forwarded"; cat "$W/out"; }
[ "`count 'notahost'`" = 0 ] && ok "a quoted @ in a template is not a target" || { bad "template"; cat "$W/out"; }
has "[rlog003w] \`/etc/rsyslog.d/old' will be ignored: rsyslog only reads \`*.conf' in \`/etc/rsyslog.d'." &&
  ok "a stray file in rsyslog.d: rlog003w" || { bad "stray"; cat "$W/out"; }
[ "`count 'rlog002i'`" = 0 ] && ok "forwarding configured: no rlog002i" || { bad "both verdicts"; cat "$W/out"; }
grep -q "$r" "$W/out" && bad "a finding names where the root is on this host" || ok "findings name the root's own paths"

# local logging only, then no syslog at all: rlog002i either way
L=$W/local
mkdir -p "$L/etc" "$L/etc/rsyslog.d"
# with the commented forwarding example RHEL 7 ships, which forwards nothing
printf '$IncludeConfig /etc/rsyslog.d/*.conf\n*.* /var/log/messages\n#*.* @@remote-host:514\n# *.* action(type="omfwd" target="example.com" port="514")\n' > "$L/etc/rsyslog.conf"
cp "$W/tigris.conf.base" "$W/tigris.conf"
{ echo "Tigris_Sysctl_Root='$L'"; echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_remotelog ) 2>&1 | join > "$W/local.out"
grep -F -q '[rlog002i] No remote logging is configured: rsyslog keeps every log on this host.' "$W/local.out" &&
  [ "`grep -F -c 'rlog002i' "$W/local.out"`" = 1 ] &&
  ! grep -q 'rlog001i' "$W/local.out" &&
  ok "local logging only, a commented forwarding example: rlog002i, once" || { bad "local"; cat "$W/local.out"; }

mkdir -p "$W/none/etc"
cp "$W/tigris.conf.base" "$W/tigris.conf"
{ echo "Tigris_Sysctl_Root='$W/none'"; echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_remotelog ) 2>&1 | join > "$W/none.out"
grep -F -q '[rlog002i] No remote logging is configured, and no rsyslog, syslog-ng or syslogd configuration was found.' "$W/none.out" &&
  [ "`grep -F -c 'rlog002i' "$W/none.out"`" = 1 ] &&
  ok "no syslog at all: rlog002i says so, once" || { bad "none"; cat "$W/none.out"; }

# an offline root (TIGRIS_ROOT, as tigris --root sets it)
R=$W/img
mkdir -p "$R/etc"
printf '*.* @offsite.example\n' > "$R/etc/rsyslog.conf"
cp "$W/tigris.conf.base" "$W/tigris.conf"; echo "Tigris_Show_INFO_Msgs=Y" >> "$W/tigris.conf"
( cd "$W" && TIGRIS_ROOT=$R TIGERHOMEDIR=$W sh ./systems/Linux/2/check_remotelog ) 2>&1 | join > "$W/off"
grep -F -q '[rlog001i] Logs are forwarded to @offsite.example (rsyslog).' "$W/off" &&
  ok "offline root: the forwarding, by the root's own configuration" || { bad "offline"; cat "$W/off"; }
grep -q "$R" "$W/off" && bad "offline root: a finding names where the root is on this host" || ok "offline root: findings name the root's own paths"

# rsyslog actions over several lines, omrelp both ways, a legacy action
# with a template, and an action inside a block comment; syslog-ng's
# network() over several lines, sources and a commented destination
M=$W/multi
mkdir -p "$M/etc/rsyslog.d" "$M/etc/syslog-ng"
printf 'module(load="omrelp")\n$IncludeConfig /etc/rsyslog.d/*.conf\n/* the old relay, kept for reference:\n*.* action(type="omfwd" target="commented.example") */\n*.* /var/log/messages\n' > "$M/etc/rsyslog.conf"
printf '*.* action(type="omfwd"\n           Target="multi.example"\n           port="514" # the collector\n           protocol="tcp")\n' > "$M/etc/rsyslog.d/30-multi.conf"
printf 'auth.* action(type="omrelp" target="relp.example" port="2514")\n' > "$M/etc/rsyslog.d/40-relp.conf"
printf '*.* :omrelp:legacyrelp.example:2514;RSYSLOG_ForwardFormat\nmail.* @@tmpl.example:514;RSYSLOG_ForwardFormat\n' > "$M/etc/rsyslog.d/50-legacy.conf"
printf '@version: 4.0\nsource s_net { network(ip("0.0.0.0") port(514)); };\nsource s_udp { udp(ip(0.0.0.0) port(514)); };\ndestination d_net {\n  network(\n    "ngmulti.example"\n    port(6514)\n    transport("tls"));\n};\n# destination d_old { tcp("ngcommented.example"); };\n' > "$M/etc/syslog-ng/syslog-ng.conf"
cp "$W/tigris.conf.base" "$W/tigris.conf"; echo "Tigris_Show_INFO_Msgs=Y" >> "$W/tigris.conf"
( cd "$W" && TIGRIS_ROOT=$M TIGERHOMEDIR=$W sh ./systems/Linux/2/check_remotelog ) 2>&1 | join > "$W/multi.out"
grep -F -q '[rlog001i] Logs are forwarded to @@tmpl.example:514, multi.example, legacyrelp.example:2514, relp.example, ngmulti.example (rsyslog and syslog-ng).' "$W/multi.out" &&
  ok "action() over lines, omrelp, :omrelp:, a template after @@, network() over lines: rlog001i" || { bad "multi"; cat "$W/multi.out"; }
grep -q 'commented\|0\.0\.0\.0\| ip' "$W/multi.out" && { bad "a comment or a source taken for a target"; cat "$W/multi.out"; } ||
  ok "comments and syslog-ng sources are no targets"

# the classic syslogd: /etc/syslog.conf and /etc/syslog.d, read where a
# syslogd is installed; without one they are a leftover nothing reads
C=$W/classic
mkdir -p "$C/etc/syslog.d" "$C/usr/sbin"
printf '#!/bin/sh\n' > "$C/usr/sbin/syslogd"
printf '*.info;mail.none\t/var/log/messages\n# *.*\t@commented.example\n*.*\t@classic.example\n' > "$C/etc/syslog.conf"
printf 'auth.*\t@sd.example\n' > "$C/etc/syslog.d/remote.conf"
( cd "$W" && TIGRIS_ROOT=$C TIGERHOMEDIR=$W sh ./systems/Linux/2/check_remotelog ) 2>&1 | join > "$W/classic.out"
grep -F -q '[rlog001i] Logs are forwarded to @classic.example, @sd.example (syslogd).' "$W/classic.out" &&
  ! grep -q 'commented' "$W/classic.out" &&
  ok "syslog.conf and syslog.d @host, with a syslogd installed: rlog001i" || { bad "classic"; cat "$W/classic.out"; }
rm "$C/usr/sbin/syslogd"
printf '*.* /var/log/messages\n' > "$C/etc/rsyslog.conf"
( cd "$W" && TIGRIS_ROOT=$C TIGERHOMEDIR=$W sh ./systems/Linux/2/check_remotelog ) 2>&1 | join > "$W/classic.out"
grep -F -q '[rlog002i] No remote logging is configured: rsyslog keeps every log on this host.' "$W/classic.out" &&
  ok "a syslog.conf with no syslogd to read it: not read" || { bad "classic leftover"; cat "$W/classic.out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
