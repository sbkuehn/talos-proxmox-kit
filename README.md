# talos-proxmox-kit

By Shannon Eldridge-Kuehn · Last updated November 7, 2026

Scripts for building a highly available Talos Linux Kubernetes cluster on a
three host Proxmox cluster, with Cilium networking, MetalLB load balancing,
and Envoy Gateway as the front door for web apps.
Companion repo for the [Cloudy Musings](https://www.shankuehn.io) post
"Talos on Proxmox: What Actually Worked (and the Boot Loop That Taught Me Why)."

## What you get

| Piece | Detail |
|---|---|
| Hypervisor | 3 Proxmox VE hosts (Intel NUCs, 64 GB RAM each) |
| Nodes | 3 control planes + 3 workers, one of each per host |
| OS | Talos Linux v1.14.4 (nocloud image from the Image Factory), Kubernetes v1.37 |
| API | Floating VIP built into Talos, no external load balancer |
| CNI | Cilium 1.20.4 with Hubble (Flannel never installed) |
| Load balancer | MetalLB in L2 mode |
| Front door | Envoy Gateway (Gateway API) on one fixed IP, routing by hostname |

## Prerequisites

On your workstation: `talosctl`, `kubectl`, `helm`, `cilium-cli`.

```bash
brew install siderolabs/tap/talosctl kubectl helm cilium-cli
```

SSH key access to `root` on every Proxmox host:

```bash
ssh-copy-id root@<host>
```

On your network: a static IP for the VIP and for every node, a range for
MetalLB, and all of them excluded from DHCP.

## Usage

1. Edit `config.env` with your IPs, hosts, VM sizes and schematic ID.
2. Run the steps in order:

```bash
./proxmox-host-prep.sh          # only fixes hosts with an e1000e NIC
./01-proxmox-vms.sh             # creates and boots the VMs from the Talos ISO
cp maintenance-ips.env.example maintenance-ips.env   # fill in DHCP IPs from each console
./02-talos-config.sh            # generates and validates every node config locally
./03-apply-and-bootstrap.sh     # installs Talos, bootstraps etcd, writes kubeconfig
./04-cilium.sh                  # installs Cilium + Hubble
./05-metallb.sh                 # installs MetalLB with your IP range
./06-envoy-gateway.sh           # shared gateway on a fixed IP, Hubble UI at hubble.<domain>
```

`teardown.sh` removes the VMs (it asks for confirmation first).

## Gotchas this kit already handles

| Symptom | Cause | Fix in the kit |
|---|---|---|
| VM boot loops at the bootloader countdown | CLI-created VMs default to the `kvm64` CPU type; Talos needs x86-64-v2 | `--cpu x86-64-v2-AES` |
| Blank console stuck on "starting serial terminal" | Serial-only display | Default VGA |
| `UnattendedInstallConfig is incompatible with v1alpha1 config` | Talos 1.12+ moved install and DNS settings into their own documents | Patches target the new documents |
| `provisioning.diskSelector.match is required` | Patching a new-style document replaces it entirely | Patches carry the full document |
| Hubble can't reach DNS, "no route to host" | Leftover Flannel state after a CNI swap | Flannel is removed before first boot |
| A Proxmox host drops off the network, link still UP | Intel e1000e hardware hang | `proxmox-host-prep.sh` disables offloads |
| MetalLB speaker pods blocked | Talos pod security defaults | Namespace labeled privileged |
| Gateway IP changes after a rebuild, breaking DNS | MetalLB hands out the next free address | Gateway IP pinned with an EnvoyProxy annotation |
| ingress-nginx examples everywhere | ingress-nginx was retired in March 2026 | Envoy Gateway and the Gateway API instead |

## Secrets

`02-talos-config.sh` writes configs and `talosconfig` to `~/.talos/<cluster>/`,
outside this repo. Those files are your cluster's keys. Back them up and never
commit them.
