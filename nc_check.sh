#!/usr/bin/env bash
# Network Channel registry/chart check for Prisma AIRS AI Red Teaming - NETHERLANDS TENANT BASED.
# No cluster needed. Proves: registry auth -> helm login -> chart pull ->
# image(s) referenced by the chart -> docker auth -> image manifest reachable.
#
#   export NC_USER='<registry username from SCM>'
#   export NC_PASS='<registry password from SCM>'
#   bash nc_check.sh
set -u
REG="${NC_REG:-registry-nl.ai-red-teaming.paloaltonetworks.com}"
CHART="${NC_CHART:-oci://$REG/pairs-redteam-prd-fckx/red-teaming-onprem/charts-nl/panw-network-client}"
VER="${NC_VER:-1.5.0}"
: "${NC_USER:?set NC_USER}"; : "${NC_PASS:?set NC_PASS}"
G="\033[32m"; R="\033[31m"; Y="\033[33m"; X="\033[0m"
ok(){ echo -e "${G}PASS${X} $1"; } ; bad(){ echo -e "${R}FAIL${X} $1"; } ; note(){ echo -e "${Y}note${X} $1"; }
W="$(mktemp -d)"; cd "$W"

echo "== 1. registry auth (curl /v2/) =="
code=$(curl -sS -o /dev/null -w '%{http_code}' -u "$NC_USER:$NC_PASS" "https://$REG/v2/")
case "$code" in
  200) ok "credentials accepted by $REG";;
  401) bad "401: wrong username/password pair (use the registry pair, not client id/secret), or the pull secret was regenerated"; exit 1;;
  000) bad "no connection: egress/DNS to $REG blocked"; exit 1;;
  *)   bad "HTTP $code from /v2/";;
esac

echo "== 2. helm registry login =="
if helm registry login "$REG" --username "$NC_USER" --password "$NC_PASS" >/dev/null 2>&1; then ok "helm login"; else bad "helm login"; exit 1; fi

echo "== 3. helm pull chart $VER =="
if helm pull "$CHART" --version "$VER" >/dev/null 2>&1; then
  TGZ=$(ls panw-network-client-*.tgz | head -1); ok "pulled $TGZ ($(du -h "$TGZ" | cut -f1))"
else
  bad "chart pull: check path/version (list via: helm show chart $CHART --version $VER)"; exit 1
fi

echo "== 4. images referenced by the chart =="
helm show values "$TGZ" > values.yaml
grep -nE '^\s*(image|repository|registry|tag):' values.yaml | sed 's/^/   /'
# render with dummy config so templates expand, then collect every image: line
helm template nc "$TGZ" --set config.clientId=x --set config.clientSecret=y --set config.channelId=z \
  > rendered.yaml 2>/dev/null && ok "chart renders with dummy clientId/secret/channelId" || note "helm template failed; fine if the chart needs extra values"
IMAGES=$(grep -E '^\s*image:' rendered.yaml | awk '{print $2}' | tr -d '"' | sort -u)
if [ -z "$IMAGES" ]; then note "no image: lines found in rendered output; read values.yaml above"; else echo "$IMAGES" | sed 's/^/   image: /'; fi

echo "== 5. docker auth + image manifest(s) =="
if command -v docker >/dev/null; then
  if echo "$NC_PASS" | docker login "$REG" -u "$NC_USER" --password-stdin >/dev/null 2>&1; then ok "docker login"; else bad "docker login"; fi
  for img in $IMAGES; do
    if docker manifest inspect "$img" >/dev/null 2>&1; then ok "manifest reachable: $img"; else bad "manifest NOT reachable: $img (proxy this path too)"; fi
  done
else
  note "docker not on PATH; skip image check"
fi

echo "== 6. pull secret (client-side dry run, no cluster) =="
if command -v kubectl >/dev/null; then
  kubectl create secret docker-registry airs-pull-secret --docker-server="$REG" \
    --docker-username="$NC_USER" --docker-password="$NC_PASS" --dry-run=client -o yaml >/dev/null \
    && ok "secret manifest generates" || bad "kubectl secret dry-run"
else note "kubectl not on PATH; skip"; fi

echo; echo "work dir: $W   (chart tgz, values.yaml, rendered.yaml)"
