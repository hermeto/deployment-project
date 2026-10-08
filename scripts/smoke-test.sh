#!/usr/bin/env bash
# End-to-end check of a GitOps deployment.
#
# Proves that the whole pipeline works, not just that pods are running:
#   1. Argo CD is rolled out;
#   2. every Application is Synced and Healthy (root, argocd, one go-app-<env> per environment);
#   3. in each environment, go-app is rolled out, answers through its Service from another namespace
#      (Service routing + NetworkPolicy), reports the version Git declares, and its namespace rejects
#      pods that violate the `restricted` Pod Security Standard;
#   4. optionally (SELF_HEAL_CHECK=true), a resource deleted by hand is recreated by Argo CD.
#
# Usage: scripts/smoke-test.sh
# Environment:
#   KUBE_CONTEXT      kubeconfig context (default: current context)
#   TIMEOUT           seconds to wait for each condition (default: 300)
#   SELF_HEAL_CHECK   delete the dev Service and wait for Argo CD to restore it (default: false — it is disruptive)
set -euo pipefail

TIMEOUT="${TIMEOUT:-300}"
SELF_HEAL_CHECK="${SELF_HEAL_CHECK:-false}"
ARGOCD_NAMESPACE=argocd
SMOKE_NAMESPACE=smoke-test
CURL_IMAGE="curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777"

# Written for bash 3.2 (macOS) too: no mapfile, no empty arrays under `set -u`.
k() { if [[ -n "${KUBE_CONTEXT:-}" ]]; then kubectl --context "$KUBE_CONTEXT" "$@"; else kubectl "$@"; fi; }

for bin in kubectl jq; do
  command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 1; }
done

pass() { printf '  \033[32mok\033[0m   %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

# retry <description> <command...>: runs the command every 5s until it succeeds or TIMEOUT expires.
retry() {
  local description="$1"; shift
  local deadline=$((SECONDS + TIMEOUT))
  until "$@" >/dev/null 2>&1; do
    if ((SECONDS >= deadline)); then
      echo "last attempt output:" >&2
      "$@" >&2 || true
      fail "$description (timed out after ${TIMEOUT}s)"
    fi
    sleep 5
  done
  pass "$description"
}

cleanup() {
  k delete namespace "$SMOKE_NAMESPACE" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

# app_is <application> <sync status> <health status>
app_is() {
  local status
  status=$(k -n "$ARGOCD_NAMESPACE" get application "$1" -o json | jq -r '"\(.status.sync.status)/\(.status.health.status)"')
  [[ "$status" == "$2/$3" ]] || { echo "application $1 is $status, want $2/$3"; return 1; }
}

# http_get <url> <expected status>: curl from the smoke-test namespace, prints the body.
http_get() {
  local out code
  out=$(k -n "$SMOKE_NAMESPACE" exec curl -- curl -sS --max-time 5 -w '\n%{http_code}' "$1") || return 1
  code="${out##*$'\n'}"
  [[ "$code" == "$2" ]] || { echo "GET $1 returned $code, want $2"; return 1; }
  printf '%s\n' "${out%$'\n'*}"
}

step "Argo CD"
for deploy in argocd-server argocd-repo-server argocd-applicationset-controller argocd-redis; do
  k -n "$ARGOCD_NAMESPACE" rollout status "deployment/$deploy" --timeout="${TIMEOUT}s" >/dev/null || fail "deployment/$deploy"
  pass "deployment/$deploy"
done
k -n "$ARGOCD_NAMESPACE" rollout status statefulset/argocd-application-controller --timeout="${TIMEOUT}s" >/dev/null ||
  fail "statefulset/argocd-application-controller"
pass "statefulset/argocd-application-controller"

step "Applications"
retry "application root is Synced/Healthy" app_is root Synced Healthy
# Root creates the other Applications: list them once it is synced.
for app in $(k -n "$ARGOCD_NAMESPACE" get applications -o jsonpath='{.items[*].metadata.name}'); do
  [[ "$app" == root ]] && continue
  retry "application $app is Synced/Healthy" app_is "$app" Synced Healthy
done
# "<environment> <namespace>" per go-app Application.
envs=$(k -n "$ARGOCD_NAMESPACE" get applications -l app.kubernetes.io/name=go-app \
  -o jsonpath='{range .items[*]}{.metadata.labels.environment}{" "}{.spec.destination.namespace}{"\n"}{end}')
[[ -n "$envs" ]] || fail "no go-app Application found"

step "Test client (namespace $SMOKE_NAMESPACE)"
k create namespace "$SMOKE_NAMESPACE" --dry-run=client -o yaml | k apply -f - >/dev/null
k -n "$SMOKE_NAMESPACE" run curl --image="$CURL_IMAGE" --restart=Never --command \
  --overrides='{"spec":{"automountServiceAccountToken":false,"securityContext":{"runAsNonRoot":true,"runAsUser":100,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"curl","image":"'"$CURL_IMAGE"'","command":["sleep","3600"],"securityContext":{"allowPrivilegeEscalation":false,"readOnlyRootFilesystem":true,"capabilities":{"drop":["ALL"]}}}]}}' \
  -- sleep 3600 >/dev/null
k -n "$SMOKE_NAMESPACE" wait --for=condition=Ready pod/curl --timeout="${TIMEOUT}s" >/dev/null || fail "pod/curl"
pass "pod/curl"

# Read from fd 3 so that no command in the loop can consume the list from stdin.
while read -r env ns <&3; do
  step "go-app in $env (namespace $ns)"

  k -n "$ns" rollout status deployment/go-app --timeout="${TIMEOUT}s" >/dev/null || fail "deployment/go-app"
  pass "deployment/go-app rolled out ($(k -n "$ns" get deployment go-app -o jsonpath='{.status.readyReplicas}') ready)"

  image=$(k -n "$ns" get deployment go-app -o jsonpath='{.spec.template.spec.containers[0].image}')
  want_version="${image##*:}"
  url="http://go-app.$ns.svc.cluster.local"

  retry "GET /healthz" http_get "$url/healthz" 200
  retry "GET /readyz" http_get "$url/readyz" 200
  body=$(http_get "$url/" 200) || fail "GET /"
  got_version=$(jq -r .version <<<"$body")
  [[ "$image" == *@sha256:* || "$got_version" == "$want_version" ]] ||
    fail "GET / reports version $got_version, the Deployment runs $image"
  pass "GET / answers version $got_version"

  [[ "$(k get namespace "$ns" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')" == restricted ]] ||
    fail "namespace $ns does not enforce the restricted Pod Security Standard"
  if out=$(k -n "$ns" run psa-check --image=busybox --restart=Never --dry-run=server \
    --overrides='{"spec":{"containers":[{"name":"psa-check","image":"busybox","securityContext":{"privileged":true}}]}}' 2>&1); then
    fail "a privileged pod was admitted in $ns"
  fi
  [[ "$out" == *PodSecurity* ]] || fail "unexpected error creating a privileged pod: $out"
  pass "privileged pods are rejected (Pod Security: restricted)"
done 3<<<"$envs"

if [[ "$SELF_HEAL_CHECK" == "true" ]]; then
  read -r env ns <<<"$(head -n 1 <<<"$envs")"
  step "Self-heal ($env)"
  uid=$(k -n "$ns" get service go-app -o jsonpath='{.metadata.uid}')
  k -n "$ns" delete service go-app --wait=true >/dev/null
  service_recreated() { [[ "$(k -n "$ns" get service go-app -o jsonpath='{.metadata.uid}')" != "$uid" ]]; }
  retry "Argo CD recreated service/go-app" service_recreated
  retry "application go-app-$env is Synced/Healthy again" app_is "go-app-$env" Synced Healthy
fi

printf '\n\033[32mAll smoke tests passed.\033[0m\n'
