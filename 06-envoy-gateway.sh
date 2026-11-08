#!/usr/bin/env bash
# Installs Envoy Gateway and creates one shared Gateway on a fixed MetalLB IP.
# Every web app then gets a hostname through an HTTPRoute pointing at it.
# Hubble UI is the first app: http://hubble.<DOMAIN>
#
# Envoy Gateway implements the Kubernetes Gateway API. It replaces
# ingress-nginx, which the Kubernetes project retired in March 2026.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env

helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version "${ENVOY_GATEWAY_VERSION}" \
  -n envoy-gateway-system --create-namespace
kubectl wait --timeout=5m -n envoy-gateway-system \
  deployment/envoy-gateway --for=condition=Available

# The EnvoyProxy resource pins the gateway's MetalLB IP so DNS never has to change.
kubectl apply -f - <<EOF
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: lab-proxy
  namespace: envoy-gateway-system
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        annotations:
          metallb.io/loadBalancerIPs: ${GATEWAY_IP}
---
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: lab-gateway
  namespace: envoy-gateway-system
spec:
  gatewayClassName: eg
  infrastructure:
    parametersRef:
      group: gateway.envoyproxy.io
      kind: EnvoyProxy
      name: lab-proxy
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hubble-ui
  namespace: kube-system
spec:
  parentRefs:
    - name: lab-gateway
      namespace: envoy-gateway-system
  hostnames:
    - hubble.${DOMAIN}
  rules:
    - backendRefs:
        - name: hubble-ui
          port: 80
EOF

kubectl -n envoy-gateway-system wait --for=condition=Programmed \
  gateway/lab-gateway --timeout=3m
kubectl -n envoy-gateway-system get gateway lab-gateway

printf "==> testing hubble.%s through %s: " "$DOMAIN" "$GATEWAY_IP"
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: hubble.${DOMAIN}" "http://${GATEWAY_IP}/" || true

echo
echo "Expect 200. Then add a DNS A record: hubble.${DOMAIN} -> ${GATEWAY_IP}"
echo "Each new app needs an HTTPRoute like the one above plus one DNS record"
echo "(or a single wildcard record such as *.apps.${DOMAIN})."
