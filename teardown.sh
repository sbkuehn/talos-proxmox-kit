#!/usr/bin/env bash
# Stops and destroys every Talos VM listed in config.env. Asks first.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env

echo "This destroys these VMs and their disks:"
echo "$NODES" | awk 'NF {printf "  %s  vmid %s  on %s\n", $1, $4, $3}'
read -r -p "Type the cluster name (${CLUSTER_NAME}) to continue: " answer
[ "$answer" = "$CLUSTER_NAME" ] || { echo "Aborted."; exit 1; }

echo "$NODES" | while read -r name role host vmid ip wmem; do
  [ -z "$name" ] && continue
  echo "==> ${host}: destroying ${vmid} (${name})"
  ssh -n "root@${host}" "qm stop ${vmid} --skiplock 2>/dev/null; qm destroy ${vmid} --purge 2>/dev/null || true"
done

echo "VMs removed. Configs in ${OUT_DIR} are untouched."
echo "Rebuild with the same configs: run 01, then 03, 04, 05."
echo "Want fresh keys instead? Run FORCE=1 ./02-talos-config.sh first."
