#!/usr/bin/env bash
# installcheck.sh <node> - install the node's kit (and the M4 kit it requires,
# if M4 is not installed), verify it, generate and run a parser with it, and
# remove what it installed.  This changes the system while it runs (PCSI
# database, SYS$COMMON:[BISON] and [M4], BISON$ROOT, M4$ROOT); run kit.sh
# first, and kit.sh in vms-m4 for the node.
# Output: out/install-<node>.txt (don't redirect this script's stdout there).
set -euo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: installcheck.sh <node>}
. "$top/upstream.conf"
REMOTE=$(echo "$UPSTREAM_NAME-$UPSTREAM_VERSION" | tr . _ | tr a-z A-Z)
"$top/tools/vms.sh" "$node" put "$top/tools/vms_installcheck.com" >/dev/null
read -r _ _ _ _ _ WORKDIR _ < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")
mkdir -p "$top/out"
log=$top/out/install-$node.txt
job=$top/cache/installcheck-$node.com
printf '$ set noon\n$ @%sVMS_INSTALLCHECK.COM %s %s\n' "$WORKDIR" "$REMOTE" "$M4_TREE" > "$job"
VMS_TIMEOUT=1800 "$top/tools/vms.sh" "$node" run "$job" > "$log" 2>&1
grep -aE 'install status|Installed|startup procedure|data file|skeleton|BISON_[A-Z_]*: |SUCREMOVE|after removal|items found' "$log"
for check in VERSION GENERATE PARSER_RUNS ERROR_SEVERITY; do
    grep -aq "BISON_$check: PASS" "$log" || { echo "installcheck: BISON_$check did not pass" >&2; exit 1; }
done
grep -aq 'BISON\$ROOT after removal: \[\]' "$log" &&
    grep -aq 'files after removal: \[\]' "$log" &&
    grep -aq 'startup after removal: \[\]' "$log"
