#!/bin/sh
#
# tests/databases_check.sh - check_databases against a root of its own
#
# A fake root with a MySQL enabling everything bad through an included
# file (and a [mysqldump] user=root that must not count), a
# client-only local-infile in /etc/my.cnf, exposed datadir and
# debian.cnf; a PostgreSQL with trust, md5, ssl off on a network
# socket and an exposed data directory, plus a Red Hat layout testing
# the PG_VERSION fallback; and Redis configurations open, locked with
# a password, locked with ACLs, and socket-only; a MongoDB open to
# the network without auth or TLS and an Oracle home allowing pre-12c
# logons with no valid-node checking. Then a clean root (nothing), a
# loopback-only MongoDB without auth, and an offline root.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
cp "$W/tigerrc" "$W/tigerrc.base"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
join() {
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--'
}
run() {  # run ROOT OUTFILE: check_databases against ROOT
  cp "$W/tigerrc.base" "$W/tigerrc"
  { echo "Tiger_Sysctl_Root='$1'"; echo "Tiger_Show_INFO_Msgs=Y"; } >> "$W/tigerrc"
  ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_databases ) 2>&1 | join > "$2"
}

r="$W/root"
mkdir -p "$r/etc/mysql/conf.d" "$r/etc/postgresql/16/main" "$r/var/lib/mysql" \
  "$r/var/lib/postgresql/16/main" "$r/var/lib/pgsql/data" "$r/etc/redis"
printf '[mysqld]\nuser = mysql\ndatadir = /var/lib/mysql\n!includedir /etc/mysql/conf.d/\n[mysqldump]\nuser = root\n' > "$r/etc/mysql/my.cnf"
printf '[mysqld]\nskip-grant-tables\nlocal-infile = ON\nuser = root\n' > "$r/etc/mysql/conf.d/bad.cnf"
printf '[client]\nlocal-infile = 1\n' > "$r/etc/my.cnf"
printf 'proof that bad.cnf was read\n' > "$r/etc/mysql/debian.cnf"
chmod 755 "$r/var/lib/mysql"; chmod 644 "$r/etc/mysql/debian.cnf"
printf "data_directory = '/var/lib/postgresql/16/main'\npassword_encryption = md5\nssl = off\nlisten_addresses = 'localhost, 192.168.7.7'\n" > "$r/etc/postgresql/16/main/postgresql.conf"
printf 'local all all peer\nhost all all 0.0.0.0/0 trust\nhost all all ::/0 scram-sha-256\n' > "$r/etc/postgresql/16/main/pg_hba.conf"
chmod 755 "$r/var/lib/postgresql/16/main"
printf "# nothing set\n" > "$r/var/lib/pgsql/data/postgresql.conf"
printf '16\n' > "$r/var/lib/pgsql/data/PG_VERSION"
chmod 755 "$r/var/lib/pgsql/data"
printf 'bind 0.0.0.0\nprotected-mode no\n' > "$r/etc/redis/redis.conf"
printf 'bind 127.0.0.1\nrequirepass s3cret\n' > "$r/etc/redis/open.conf"
chmod 644 "$r/etc/redis/open.conf"
printf 'user default on >s3cret\nprotected-mode no\nbind 0.0.0.0\n' > "$r/etc/redis/acl.conf"
chmod 600 "$r/etc/redis/acl.conf"
printf 'user default off\nuser bob on >s3cret\nprotected-mode no\nbind 0.0.0.0\n' > "$r/etc/redis/acl3.conf"
chmod 600 "$r/etc/redis/acl3.conf"
printf 'user default off\nuser bob on nopass\nprotected-mode no\nbind 0.0.0.0\n' > "$r/etc/redis/acl4.conf"
printf 'requirepass s3cret\nuser bob on nopass\nprotected-mode no\nbind 0.0.0.0\n' > "$r/etc/redis/acl5.conf"
chmod 600 "$r/etc/redis/acl5.conf"
printf 'port 0\nprotected-mode no\nbind 0.0.0.0\n' > "$r/etc/redis/port0.conf"
mkdir -p "$r/var/lib/mongodb"
cat > "$r/etc/mongod.conf" <<'EOF'
storage:
  dbPath: /var/lib/mongodb
net:
  bindIp: 0.0.0.0
security:
  authorization: disabled
EOF
chmod 755 "$r/var/lib/mongodb"
mkdir -p "$r/u01/app/oracle/product/19c/dbhome_1/network/admin"
printf 'ORCL:/u01/app/oracle/product/19c/dbhome_1:Y\n' > "$r/etc/oratab"
cat > "$r/u01/app/oracle/product/19c/dbhome_1/network/admin/sqlnet.ora" <<'EOF'
SQLNET.ALLOWED_LOGON_VERSION_SERVER=11
EOF
run "$r" "$W/out"
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -F -c -- "$1" "$W/out"; }

has "[dbs001f] MySQL runs with skip-grant-tables (/etc/mysql/conf.d/bad.cnf): anyone connecting has every privilege without a password." &&
  ok "skip-grant-tables in an included file: dbs001f" || { bad "skip-grant"; cat "$W/out"; }
has "[dbs002w] LOAD DATA LOCAL is enabled (/etc/mysql/conf.d/bad.cnf): a SQL user reads files off the machine connecting." &&
  has "[dbs002w] LOAD DATA LOCAL is enabled for clients (/etc/my.cnf): this host's tools send local files to any server they load data to." &&
  [ "`count 'dbs002w'`" = 2 ] &&
  ok "local-infile on the server and on clients: dbs002w twice" || { bad "local-infile"; cat "$W/out"; }
[ "`count 'dbs004f'`" = 1 ] && has "[dbs004f] mysqld runs as root (user=root in /etc/mysql/conf.d/bad.cnf):" &&
  ok "user=root in [mysqld] (once; [mysqldump]'s does not count): dbs004f" || { bad "user root"; cat "$W/out"; }
has "[dbs003f] MySQL's data directory \`/var/lib/mysql' is readable by anyone: every table can be copied." &&
  has "[dbs003f] The maintenance password in \`/etc/mysql/debian.cnf' is readable by anyone." &&
  ok "exposed datadir and debian.cnf: dbs003f" || { bad "mysql secrets"; cat "$W/out"; }
has "Line 2 of \`/etc/postgresql/16/main/pg_hba.conf' authenticates with 'trust': no password is asked." &&
  ok "trust in pg_hba.conf: dbs005f with its line" || { bad "trust"; cat "$W/out"; }
has "[dbs006w] Passwords are stored as md5 (/etc/postgresql/16/main/postgresql.conf):" &&
  ok "md5 passwords: dbs006w" || { bad "md5"; cat "$W/out"; }
has "[dbs008w] PostgreSQL takes unencrypted connections from the network (ssl is off in /etc/postgresql/16/main/postgresql.conf, listening on 192.168.7.7)." &&
  ok "ssl off on a network socket: dbs008w" || { bad "ssl off"; cat "$W/out"; }
has "[dbs007f] PostgreSQL's data directory \`/var/lib/postgresql/16/main' is readable by anyone:" &&
  has "[dbs007f] PostgreSQL's data directory \`/var/lib/pgsql/data' is readable by anyone:" &&
  ok "exposed data directories, Debian and Red Hat layouts: dbs007f" || { bad "pg secrets"; cat "$W/out"; }
[ "`count 'dbs009f'`" = 3 ] &&
  has "(protected-mode no in /etc/redis/redis.conf, no requirepass, bound to 0.0.0.0):" &&
  has "(protected-mode no in /etc/redis/acl4.conf, users without a password (bob), bound to 0.0.0.0):" &&
  has "(protected-mode no in /etc/redis/acl5.conf, users without a password (bob), bound to 0.0.0.0):" &&
  ok "three open redis configurations (two via nopass ACL users): dbs009f" || { bad "redis open"; cat "$W/out"; }
has "[dbs010f] The password in \`/etc/redis/open.conf' is readable by anyone." &&
  [ "`count 'dbs010f'`" = 1 ] &&
  ok "a world-readable password: dbs010f, once" || { bad "redis password"; cat "$W/out"; }
has "[dbs011f] MongoDB takes unauthenticated connections from the network (no authorization in /etc/mongod.conf, bound to 0.0.0.0):" &&
  has "[dbs013w] MongoDB takes unencrypted connections from the network (no TLS in /etc/mongod.conf, bound to 0.0.0.0)." &&
  has "[dbs014f] MongoDB's data directory \`/var/lib/mongodb' is readable by anyone:" &&
  ok "MongoDB open without auth or TLS, exposed dbPath: dbs011f, dbs013w, dbs014f" || { bad "mongo open"; cat "$W/out"; }
has "[dbs015w] Oracle allows pre-12c logons (11 in /u01/app/oracle/product/19c/dbhome_1/network/admin/sqlnet.ora):" &&
  has "[dbs016w] Oracle checks no connecting address (/u01/app/oracle/product/19c/dbhome_1/network/admin/sqlnet.ora sets no TCP.VALIDNODE_CHECKING=yes):" &&
  ok "Oracle via oratab, weak logons and no valid-node checking: dbs015w, dbs016w" || { bad "oracle"; cat "$W/out"; }
grep -q "$r" "$W/out" && bad "a finding names where the root is on this host" || ok "findings name the root's own paths"

# order across an include: the last value wins wherever it stands, and
# names the file it stands in
O=$W/order
mkdir -p "$O/etc/mysql/conf.d"
printf '[mysqld]\n!includedir /etc/mysql/conf.d/\nskip-grant-tables = OFF\nuser = root\n' > "$O/etc/mysql/my.cnf"
printf '[mysqld]\nskip-grant-tables\n' > "$O/etc/mysql/conf.d/on.cnf"
run "$O" "$W/order.out"
if grep -q 'dbs001f' "$W/order.out"; then
  bad "order"; cat "$W/order.out"
elif grep -F -q "[dbs004f] mysqld runs as root (user=root in /etc/mysql/my.cnf):" "$W/order.out"; then
  ok "a later OFF wins, and user=root names the main file"
else
  bad "order"; cat "$W/order.out"
fi

# a clean root: ports closed, passwords hashed, secrets alone: nothing
C=$W/clean
mkdir -p "$C/etc/mysql" "$C/var/lib/mysql" "$C/etc/postgresql/16/main" "$C/var/lib/postgresql/16/main" "$C/etc/redis"
printf '[mysqld]\nuser = mysql\nlocal-infile = 0\ndatadir = /var/lib/mysql\n' > "$C/etc/mysql/my.cnf"
printf 'x\n' > "$C/etc/mysql/debian.cnf"
chmod 700 "$C/var/lib/mysql"; chmod 600 "$C/etc/mysql/debian.cnf"
printf "data_directory = '/var/lib/postgresql/16/main'\npassword_encryption = 'scram-sha-256'\nssl = on\nlisten_addresses = 'localhost'\n" > "$C/etc/postgresql/16/main/postgresql.conf"
printf 'local all all peer\nhost all all 127.0.0.1/32 scram-sha-256\n' > "$C/etc/postgresql/16/main/pg_hba.conf"
chmod 700 "$C/var/lib/postgresql/16/main"
printf 'bind 127.0.0.1 ::1\nrequirepass s3cret\nprotected-mode yes\n' > "$C/etc/redis/redis.conf"
chmod 600 "$C/etc/redis/redis.conf"
cat > "$C/etc/mongod.conf" <<'EOF'
security:
  authorization: enabled
net:
  bindIp: localhost
  tls:
    mode: requireTLS
EOF
mkdir -p "$C/u01/app/oracle/product/19c/dbhome_1/network/admin"
printf 'ORCL:/u01/app/oracle/product/19c/dbhome_1:Y\n' > "$C/etc/oratab"
cat > "$C/u01/app/oracle/product/19c/dbhome_1/network/admin/sqlnet.ora" <<'EOF'
SQLNET.ALLOWED_LOGON_VERSION_SERVER=12
TCP.VALIDNODE_CHECKING=yes
TCP.INVITED_NODES=(db.example.com)
EOF
run "$C" "$W/clean.out"
grep -q 'dbs0[0-9][0-9]' "$W/clean.out" && { bad "clean"; cat "$W/clean.out"; } || ok "a clean root: nothing"

# loopback-only MongoDB without auth: local users are still trusted
M=$W/mongolocal
mkdir -p "$M/etc"
printf 'net:\n  bindIp: 127.0.0.1\n' > "$M/etc/mongod.conf"
run "$M" "$W/mongo.out"
grep -F -q "[dbs012w] MongoDB takes unauthenticated connections on its loopback socket (no authorization in /etc/mongod.conf):" "$W/mongo.out" &&
  ! grep -q 'dbs011f\|dbs013w\|dbs014f' "$W/mongo.out" &&
  ok "no auth on loopback only: dbs012w alone" || { bad "mongo local"; cat "$W/mongo.out"; }

# an offline root (TIGRIS_ROOT, as tigris --root sets it)
R=$W/img
mkdir -p "$R/etc/mysql" "$R/var/lib/mysql"
printf '[mysqld]\nskip-grant-tables\ndatadir = /var/lib/mysql\n' > "$R/etc/mysql/my.cnf"
chmod 755 "$R/var/lib/mysql"
cp "$W/tigerrc.base" "$W/tigerrc"; echo "Tiger_Show_INFO_Msgs=Y" >> "$W/tigerrc"
( cd "$W" && TIGRIS_ROOT=$R TIGERHOMEDIR=$W sh ./systems/Linux/2/check_databases ) 2>&1 | join > "$W/off"
grep -F -q "[dbs001f] MySQL runs with skip-grant-tables (/etc/mysql/my.cnf):" "$W/off" &&
  grep -F -q "[dbs003f] MySQL's data directory \`/var/lib/mysql' is readable by anyone:" "$W/off" &&
  ok "offline root: skip-grant-tables and the exposed datadir" || { bad "offline"; cat "$W/off"; }
grep -q "$R" "$W/off" && bad "offline root: a finding names where the root is on this host" || ok "offline root: findings name the root's own paths"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
