#!/usr/bin/env bash
# Installs MetalLB and gives it the IP range from config.env.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env

helm repo add metallb https://metallb.github.io/metallb >/dev/null 2>&1 || true
helm repo update metallb >/dev/null

# Talos enforces pod security by default. The speaker needs raw network
# access to answer ARP for service IPs, so this namespace is privileged.
kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace metallb-system --overwrite \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged

helm upgrade --install metallb metallb/metallb --namespace metallb-system --wait

# The pool CRDs only exist after the chart is installed
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lab-pool
  namespace: metallb-system
spec:
  addresses:
    - ${METALLB_RANGE}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lab-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - lab-pool
EOF

kubectl -n metallb-system get pods
kubectl -n metallb-system get ipaddresspool

echo
echo "Next: ./06-envoy-gateway.sh gives every web app a hostname on ${GATEWAY_IP}."
