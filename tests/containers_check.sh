#!/bin/sh
#
# tests/containers_check.sh - check_containers against trees of its own
#
# A /run/docker.sock (a plain file: its mode and group are what count), an
# /etc/group and /etc/passwd naming that group's members, a dockerd process
# in /proc, and the containers as docker inspect --format prints them,
# through Tigris_Container_List_Cmd: a plain one, a privileged one, a
# monitoring agent with the host's namespaces and the socket, one given
# SYS_ADMIN with /etc writable.
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

r="$W/root"; mkdir -p "$r/run" "$r/etc/docker" "$r/proc/100"
: > "$r/run/docker.sock"; chmod 660 "$r/run/docker.sock"
# as root the file would be in group 0, which is root's own: give it one
[ "`id -u`" = 0 ] && chgrp 4242 "$r/run/docker.sock"
gid=`ls -lnd "$r/run/docker.sock" | awk '{ print $4 }'`
printf 'root:x:0:\ndocker:x:%s:alice,bob\n' "$gid" > "$r/etc/group"
printf 'root:x:0:0::/root:/bin/sh\ncarol:x:1005:%s::/home/carol:/bin/sh\n' "$gid" > "$r/etc/passwd"
echo dockerd > "$r/proc/100/comm"
printf 'Name:\tdockerd\nUid:\t0\t0\t0\t0\n' > "$r/proc/100/status"
printf 'dockerd\000-H\000fd://\000--containerd=/run/containerd/containerd.sock\000' > "$r/proc/100/cmdline"
cat > "$W/list" <<'EOF'
#!/bin/sh
cat <<'EOT'
/web|false||bridge|[]|/srv/www:false
/dind|true||bridge|[]|/var/lib/docker:true
/agent|false|host|host|[]|/var/run/docker.sock:true /:false
/cfg|false||bridge|[SYS_ADMIN]|/etc:true
EOT
EOF
go() {
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { echo "Tigris_Sysctl_Root='$r'"; echo "Tigris_Container_List_Cmd='sh $W/list'"; echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_containers ) 2>&1 |
    awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
    tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out"
}
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -F -c -- "$1" "$W/out"; }

go
has '--WARN-- [cont001w] Members of the group that may use the docker socket are root in effect' && has 'Group docker: alice, bob, carol.' &&
  ok "the socket's group and its members, primary ones included: cont001w" || { bad "group"; cat "$W/out"; }
[ "`count cont002f`" = 0 ] && ok "a socket of mode 660: no cont002f" || { bad "660"; cat "$W/out"; }
has '--INFO-- [cont009i] dockerd runs as root' && ok "a root dockerd: cont009i" || { bad "rootful"; cat "$W/out"; }
has '--WARN-- [cont004w] The container dind runs privileged' && has 'The container cfg runs given [SYS_ADMIN]' && [ "`count cont004w`" = 2 ] &&
  ok "privileged, and SYS_ADMIN added: cont004w for each" || { bad "privileged"; cat "$W/out"; }
has '--WARN-- [cont005w] The container agent shares the host'"'"'s process namespace' && has '--INFO-- [cont006i] The container agent shares the host'"'"'s network namespace.' &&
  ok "host PID namespace (cont005w), host network (cont006i)" || { bad "namespaces"; cat "$W/out"; }
has '--WARN-- [cont007w] The container agent has the container engine'"'"'s socket mounted' && ok "the Docker socket mounted: cont007w" || { bad "socket mount"; cat "$W/out"; }
has '--WARN-- [cont008w] The container cfg has the host'"'"'s /etc mounted writable' && [ "`count cont008w`" = 1 ] &&
  ok "/etc writable: cont008w; the host's / read-only: not" || { bad "host mounts"; cat "$W/out"; }
[ "`count 'container web'`" = 0 ] && ok "a plain container: nothing" || { bad "web"; cat "$W/out"; }

chmod 666 "$r/run/docker.sock"; go
has '--FAIL-- [cont002f] Anyone on the system can use the docker socket' && ok "a socket of mode 666: cont002f" || { bad "666"; cat "$W/out"; }
chmod 660 "$r/run/docker.sock"

echo '{ "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2375"] }' > "$r/etc/docker/daemon.json"; go
has '--FAIL-- [cont003f] The Docker API listens on TCP without TLS' && has 'A tcp:// host is set in /etc/docker/daemon.json, and tlsverify is not.' &&
  ok "tcp:// in daemon.json, no TLS: cont003f" || { bad "tcp json"; cat "$W/out"; }
echo '{ "hosts": ["tcp://0.0.0.0:2376"], "tlsverify": true }' > "$r/etc/docker/daemon.json"; go
[ "`count cont003f`" = 0 ] && ok "tcp:// with tlsverify: nothing" || { bad "tls"; cat "$W/out"; }
rm -f "$r/etc/docker/daemon.json"
printf 'dockerd\000-H\000tcp://0.0.0.0:2375\000' > "$r/proc/100/cmdline"; go
has 'A tcp:// host is set on dockerd'"'"'s command line' && ok "-H tcp:// on dockerd's command line: cont003f" || { bad "tcp cmdline"; cat "$W/out"; }
printf 'dockerd\000-H\000fd://\000' > "$r/proc/100/cmdline"

printf 'Name:\tdockerd\nUid:\t1000\t1000\t1000\t1000\n' > "$r/proc/100/status"; go
[ "`count cont009i`" = 0 ] && ok "a dockerd running as a user (rootless): no cont009i" || { bad "rootless"; cat "$W/out"; }

rm -f "$r/run/docker.sock"; rm -rf "$r/proc/100" "$r/etc/docker"; go
[ "`count .`" = 0 ] && ok "no socket, no engine, no config: nothing said" || { bad "none"; cat "$W/out"; }

# the daemon's own configuration: writable by everyone, owned by another
# (a socket must exist or the check has nothing to judge and stays silent)
mkdir -p "$r/etc/docker" "$r/run"
: > "$r/run/docker.sock"; chmod 660 "$r/run/docker.sock"
printf '{ "hosts": ["unix:///var/run/docker.sock"] }\n' > "$r/etc/docker/daemon.json"
chmod 777 "$r/etc/docker"; chmod 666 "$r/etc/docker/daemon.json"
[ "`id -u`" = 0 ] && chown 4242:4242 "$r/etc/docker" "$r/etc/docker/daemon.json"
go
[ "`count cont011w`" = 2 ] && has "/etc/docker' is writable by everyone" && has "/etc/docker/daemon.json' is writable by everyone" &&
  ok "directory and file world-writable: cont011w for each" || { bad "writable"; cat "$W/out"; }
[ "`count cont012w`" = 2 ] && has "/etc/docker' is owned by" && has "/etc/docker/daemon.json' is owned by" &&
  ok "both owned by another: cont012w for each" || { bad "owned"; cat "$W/out"; }
chmod 755 "$r/etc/docker"; chmod 644 "$r/etc/docker/daemon.json"
[ "`id -u`" = 0 ] && chown 0:0 "$r/etc/docker" "$r/etc/docker/daemon.json"
go
[ "`count cont011w`" = 0 ] && ok "proper modes: no cont011w" || { bad "modes clean"; cat "$W/out"; }
if [ "`id -u`" = 0 ]; then
  [ "`count cont012w`" = 0 ] && ok "root-owned config: silent" || { bad "root clean"; cat "$W/out"; }
else
  [ "`count cont012w`" = 2 ] && ok "user-owned config still reported: cont012w" || { bad "user owned"; cat "$W/out"; }
fi

[ $fail -eq 0 ] && echo "PASS"
exit $fail
