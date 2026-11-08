#!/usr/bin/env bash
# Creates and starts the Talos VMs on each Proxmox host.
# Run from your workstation. Needs SSH key access to root on each host.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env

ISO_URL="https://factory.talos.dev/image/${SCHEMATIC_ID}/${TALOS_VERSION}/nocloud-amd64.iso"

# 1. Make sure every host has the ISO
for host in $(echo "$NODES" | awk 'NF {print $3}' | sort -u); do
  echo "==> ${host}: checking ISO"
  ssh "root@${host}" "test -f /var/lib/vz/template/iso/${ISO_NAME} || \
    wget -q -O /var/lib/vz/template/iso/${ISO_NAME} '${ISO_URL}'"
done

# 2. Create and start each VM
echo "$NODES" | while read -r name role host vmid ip wmem; do
  [ -z "$name" ] && continue
  if [ "$role" = "cp" ]; then
    cores=$CP_CORES; mem=$CP_MEM; disk=$CP_DISK
  else
    cores=$WORKER_CORES; mem=$wmem; disk=$WORKER_DISK
  fi

  echo "==> ${host}: VM ${vmid} (${name}) ${cores} cores, ${mem} MB, ${disk} GB"
  # Settings that matter:
  #   --cpu x86-64-v2-AES      Talos needs x86-64-v2. The CLI default (kvm64) boot loops.
  #   --boot order=scsi0;ide2  Empty disk first, ISO as fallback. After install, disk wins.
  #   no serial console        Default VGA, so the Proxmox console shows the Talos dashboard.
  ssh -n "root@${host}" "
    if qm status ${vmid} >/dev/null 2>&1; then
      echo '   already exists, skipping'
    else
      qm create ${vmid} --name ${name} --sockets 1 --cores ${cores} --memory ${mem} \
        --cpu x86-64-v2-AES --machine q35 --bios ovmf --ostype l26 \
        --efidisk0 ${STORAGE}:0,efitype=4m,pre-enrolled-keys=0 \
        --scsihw virtio-scsi-pci --scsi0 ${STORAGE}:${disk} \
        --ide2 local:iso/${ISO_NAME},media=cdrom \
        --net0 virtio,bridge=${BRIDGE} \
        --boot 'order=scsi0;ide2' --agent enabled=1 --onboot 1
      qm start ${vmid}
    fi"
done

echo
echo "Done. Open each VM console in Proxmox, note the DHCP IP on the Talos"
echo "dashboard, and fill in maintenance-ips.env before running 03."
