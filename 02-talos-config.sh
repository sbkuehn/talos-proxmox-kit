#!/usr/bin/env bash
# Generates and validates one Talos machine config per node.
# Touches nothing on the cluster. Safe to rerun.
#
# Talos 1.12+ splits config into separate documents (UnattendedInstallConfig,
# ResolverConfig, HostnameConfig, ...). Patching one of those documents
# REPLACES it, so each patch below carries the full document.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env
TALOSCTL="${TALOSCTL:-talosctl}"

if [ -f "${OUT_DIR}/talosconfig" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "${OUT_DIR}/talosconfig already exists. These are your cluster's keys."
  echo "Rerun with FORCE=1 only if you are building a brand new cluster."
  exit 1
fi

mkdir -p "${OUT_DIR}/patches"
P="${OUT_DIR}/patches"

# --- Common: installer image with our extensions, install disk, DNS ---
{
  cat <<EOF
apiVersion: v1alpha1
kind: UnattendedInstallConfig
installer:
  image: factory.talos.dev/nocloud-installer/${SCHEMATIC_ID}:${TALOS_VERSION}
provisioning:
  diskSelector:
    match: disk.dev_path == "/dev/sda"
  wipe: false
---
apiVersion: v1alpha1
kind: ResolverConfig
nameservers:
EOF
  for ns in $NAMESERVERS; do echo "  - address: ${ns}"; done
  cat <<EOF
hostDNS:
  enabled: true
  forwardKubeDNSToHost: true
EOF
} > "${P}/common.yaml"

# --- No Flannel: Cilium gets installed right after bootstrap ---
cat > "${P}/cni-none.yaml" <<'EOF'
apiVersion: v1alpha1
kind: KubeFlannelCNIConfig
$patch: delete
EOF

# --- Per node: static IP, hostname, and the VIP on control planes ---
echo "$NODES" | while read -r name role host vmid ip wmem; do
  [ -z "$name" ] && continue
  {
    cat <<EOF
machine:
  network:
    interfaces:
      - deviceSelector:
          physical: true
        dhcp: false
        addresses:
          - ${ip}/${PREFIX}
        routes:
          - network: 0.0.0.0/0
            gateway: ${GATEWAY}
EOF
    if [ "$role" = "cp" ]; then
      cat <<EOF
        vip:
          ip: ${VIP}
EOF
    fi
    cat <<EOF
---
apiVersion: v1alpha1
kind: HostnameConfig
hostname: ${name}
auto: off
EOF
  } > "${P}/${name}.yaml"
done

# --- Generate base configs, then one file per node ---
"$TALOSCTL" gen config "${CLUSTER_NAME}" "https://${VIP}:6443" \
  --output-dir "${OUT_DIR}" --config-patch "@${P}/common.yaml" \
  --with-docs=false --with-examples=false --force

for f in controlplane worker; do
  if grep -q "^kind: KubeFlannelCNIConfig" "${OUT_DIR}/${f}.yaml"; then
    "$TALOSCTL" machineconfig patch "${OUT_DIR}/${f}.yaml" --patch "@${P}/cni-none.yaml" \
      -o "${OUT_DIR}/${f}.new.yaml"
    mv "${OUT_DIR}/${f}.new.yaml" "${OUT_DIR}/${f}.yaml"
  fi
done

echo "$NODES" | while read -r name role host vmid ip wmem; do
  [ -z "$name" ] && continue
  base=worker; [ "$role" = "cp" ] && base=controlplane
  "$TALOSCTL" machineconfig patch "${OUT_DIR}/${base}.yaml" --patch "@${P}/${name}.yaml" \
    -o "${OUT_DIR}/${name}.yaml" </dev/null
  "$TALOSCTL" validate --config "${OUT_DIR}/${name}.yaml" --mode metal </dev/null
done

echo
echo "Configs are in ${OUT_DIR}. Back that folder up somewhere safe."
