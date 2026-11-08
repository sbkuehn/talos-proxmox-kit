#!/usr/bin/env bash
# Pushes each node's config, waits for the static IPs, bootstraps etcd once,
# and writes your kubeconfig.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env
TALOSCONFIG="${OUT_DIR}/talosconfig"

[ -f maintenance-ips.env ] || { echo "Create maintenance-ips.env first (see the .example)."; exit 1; }

CP_IPS=$(echo "$NODES" | awk '$2=="cp" {print $5}' | xargs)
FIRST_CP=$(echo "$CP_IPS" | awk '{print $1}')

# 1. Apply configs. --insecure only works (and is only needed) in maintenance mode.
grep -v '^\s*#' maintenance-ips.env | while read -r name dhcp; do
  [ -z "$name" ] && continue
  echo "==> ${name}: applying config via ${dhcp}"
  talosctl apply-config --insecure --nodes "$dhcp" --file "${OUT_DIR}/${name}.yaml" </dev/null
done

# 2. Point talosctl at the control planes
talosctl --talosconfig "$TALOSCONFIG" config endpoint $CP_IPS
talosctl --talosconfig "$TALOSCONFIG" config node "$FIRST_CP"

# 3. Wait for every node to install, reboot and answer on its static IP
echo "$NODES" | while read -r name role host vmid ip wmem; do
  [ -z "$name" ] && continue
  printf "==> waiting for %s on %s " "$name" "$ip"
  for _ in $(seq 1 60); do
    if talosctl --talosconfig "$TALOSCONFIG" -n "$ip" version </dev/null >/dev/null 2>&1; then
      echo "up"; continue 2
    fi
    printf "."; sleep 10
  done
  echo; echo "Timed out waiting for ${name}. Check its console."; exit 1
done

# 4. Bootstrap etcd. Exactly once, on exactly one control plane.
if talosctl --talosconfig "$TALOSCONFIG" -n "$FIRST_CP" etcd status >/dev/null 2>&1; then
  echo "==> etcd already running, skipping bootstrap"
else
  echo "==> bootstrapping etcd on ${FIRST_CP}"
  talosctl --talosconfig "$TALOSCONFIG" -n "$FIRST_CP" bootstrap
fi

# 5. Kubeconfig (merged into ~/.kube/config)
echo "==> waiting for the Kubernetes API on ${VIP}"
for _ in $(seq 1 60); do
  talosctl --talosconfig "$TALOSCONFIG" -n "$FIRST_CP" kubeconfig >/dev/null 2>&1 && \
    kubectl get nodes >/dev/null 2>&1 && break
  sleep 10
done
kubectl get nodes

echo
echo "Nodes show NotReady until Cilium is installed. That's expected. Run 04 next."
echo "Tip: export TALOSCONFIG=${TALOSCONFIG} so plain talosctl commands find this cluster."
