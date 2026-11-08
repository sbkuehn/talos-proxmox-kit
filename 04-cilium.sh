#!/usr/bin/env bash
# Installs Cilium (with Hubble) as the cluster's only CNI.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env

helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
helm repo update cilium >/dev/null

helm upgrade --install cilium cilium/cilium --version "${CILIUM_VERSION}" \
  --namespace kube-system --values manifests/cilium-values.yaml

cilium status --wait

# Clear out any pods that failed while the cluster had no networking
kubectl -n kube-system delete pods --field-selector=status.phase=Failed --ignore-not-found
kubectl -n kube-system rollout restart deployment coredns
kubectl -n kube-system rollout status deployment coredns

talosctl --talosconfig "${OUT_DIR}/talosconfig" health --wait-timeout 10m
kubectl get nodes
