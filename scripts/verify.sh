#!/usr/bin/env bash
set -euo pipefail

echo "=== Control Plane ==="
kubectl get nodes

echo ""
echo "=== DNS Resolution ==="
echo -n "$DOMAIN_NAME "
dig "$DOMAIN_NAME" +short
echo -n "www.$DOMAIN_NAME "
dig "www.$DOMAIN_NAME" +short

echo ""
echo "=== TLS Certificate ==="
kubectl get certificate -n default

echo ""
echo "=== Traefik Pods ==="
kubectl get daemonset -n traefik
kubectl get pods -n traefik -o wide

echo ""
echo "=== Site Pods ==="
kubectl get pods -n default -o wide

echo ""
echo "=== HTTPS Per-Server ==="
INVENTORY="$(dirname "$0")/../ansible/inventory/hosts.yml"
for ip in $(grep 'ansible_host:' "$INVENTORY" | awk '{print $2}'); do
  code=$(curl -sf -o /dev/null -w "%{http_code}" \
    --resolve "$DOMAIN_NAME:443:$ip" "https://$DOMAIN_NAME" || true)
  echo "$ip → $code"
done

echo ""
echo "=== Redirects ==="
curl -sf -o /dev/null -w "http://$DOMAIN_NAME → %{http_code}\n" "http://$DOMAIN_NAME" || true
curl -sf -o /dev/null -w "https://www.$DOMAIN_NAME → %{http_code}\n" "https://www.$DOMAIN_NAME" || true
