#!/usr/bin/env bash
# Host-level fixes for Intel NUC Proxmox hosts.
#
# The Intel e1000e NIC can hang under load while still reporting the link UP.
# The host goes dark (its VMs keep running) until the NIC is reset.
# Turning off TCP/generic segmentation and receive offloads prevents the hang.
# Only applied to hosts that actually use the e1000e driver.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env

for host in $(echo "$NODES" | awk 'NF {print $3}' | sort -u); do
  echo "==> ${host}"
  ssh "root@${host}" '
    IFACE=$(ip -o link show master vmbr0 | awk -F": " "!/tap|veth|fwpr/ {print \$2; exit}")
    DRIVER=$(ethtool -i "$IFACE" | awk "/^driver:/ {print \$2}")
    echo "   uplink: $IFACE  driver: $DRIVER"
    if [ "$DRIVER" = "e1000e" ]; then
      grep -q "ethtool -K $IFACE" /etc/network/interfaces || \
        sed -i "/^iface $IFACE/a\        post-up /sbin/ethtool -K $IFACE tso off gso off gro off" /etc/network/interfaces
      ethtool -K "$IFACE" tso off gso off gro off
      echo "   offloads disabled (persisted in /etc/network/interfaces)"
    else
      echo "   not e1000e, nothing to do"
    fi'
done
