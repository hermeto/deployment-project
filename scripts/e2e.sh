#!/usr/bin/env bash
# End-to-end test of the GitOps pipeline on a disposable cluster (kind), without pushing anything to GitHub:
#   1. start an in-cluster Git server (e2e/git-server.yaml);
#   2. push a snapshot of the working tree to it, uncommitted changes included;
#   3. bootstrap Argo CD pointed at that server (scripts/bootstrap.sh), twice: the second run must be a no-op;
#   4. run the smoke tests, including the self-heal check (scripts/smoke-test.sh);
#   5. change Git (scale dev to 2 replicas) and check that Argo CD rolls the change out.
#
# The go-app image must already be loaded in the cluster (`make e2e` builds and loads it).
#
# Usage: scripts/e2e.sh <argo-cd chart directory>
# Environment:
#   KUBE_CONTEXT     kubeconfig context of the disposable cluster (required)
#   TIMEOUT          seconds to wait for each condition (default: 300)
#   GIT_LOCAL_PORT   local port for the port-forward to the Git server (default: 19418)
set -euo pipefail

cd "$(dirname "$0")/.."

chart_dir="${1:?usage: $0 <argo-cd chart directory>}"
: "${KUBE_CONTEXT:?KUBE_CONTEXT must name the disposable cluster}"
export KUBE_CONTEXT
export TIMEOUT="${TIMEOUT:-300}"
local_port="${GIT_LOCAL_PORT:-19418}"
local_repo="git://127.0.0.1:$local_port/deployment-project.git"
cluster_repo="git://git-server.git-server.svc.cluster.local/deployment-project.git"

k() { kubectl --context "$KUBE_CONTEXT" "$@"; }
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

work=$(mktemp -d)
pf_pid=""
cleanup() {
  if [[ -n "$pf_pid" ]]; then kill "$pf_pid" 2>/dev/null || true; fi
  rm -rf "$work"
}
trap cleanup EXIT

export GIT_AUTHOR_NAME=e2e GIT_AUTHOR_EMAIL=e2e@example.invalid
export GIT_COMMITTER_NAME=e2e GIT_COMMITTER_EMAIL=e2e@example.invalid

step "Git server"
k apply -f e2e/git-server.yaml >/dev/null
k -n git-server rollout status deployment/git-server --timeout="${TIMEOUT}s" >/dev/null || fail "deployment/git-server"
k -n git-server port-forward svc/git-server "$local_port:9418" >/dev/null 2>&1 &
pf_pid=$!
retry "git server reachable on $local_repo" git ls-remote "$local_repo"

step "Push the working tree"
# A temporary index holds every file that is not git-ignored, so uncommitted changes are tested too.
GIT_INDEX_FILE="$work/index" git add --all
tree=$(GIT_INDEX_FILE="$work/index" git write-tree)
snapshot=$(git commit-tree --no-gpg-sign "$tree" -m "e2e snapshot of $(git rev-parse --short HEAD 2>/dev/null || echo 'an unborn branch')")
git push --quiet --force "$local_repo" "$snapshot:refs/heads/main"
pass "pushed $snapshot to main"

step "Bootstrap"
REPO_URL="$cluster_repo" REPO_REVISION=main scripts/bootstrap.sh "$chart_dir"
step "Bootstrap again (must be idempotent)"
REPO_URL="$cluster_repo" REPO_REVISION=main scripts/bootstrap.sh "$chart_dir" >/dev/null
pass "second bootstrap succeeded"

SELF_HEAL_CHECK=true scripts/smoke-test.sh

step "GitOps: a change in Git reaches the cluster"
git clone --quiet "$local_repo" "$work/repo"
values="$work/repo/environments/dev/values.yaml"
grep -q '^replicaCount: 1$' "$values" || fail "environments/dev/values.yaml no longer sets replicaCount: 1; update this test"
sed -i.bak 's/^replicaCount: 1$/replicaCount: 2/' "$values" && rm -f "$values.bak"
git -C "$work/repo" commit --quiet --no-gpg-sign -am "e2e: scale dev to 2 replicas"
git -C "$work/repo" push --quiet origin main
revision=$(git -C "$work/repo" rev-parse HEAD)
pass "pushed $revision"

k -n argocd annotate application go-app-dev argocd.argoproj.io/refresh=normal --overwrite >/dev/null
synced_to() { [[ "$(k -n argocd get application go-app-dev -o jsonpath='{.status.sync.revision}/{.status.sync.status}')" == "$1/Synced" ]]; }
retry "go-app-dev synced to $revision" synced_to "$revision"
two_ready() { [[ "$(k -n go-app-dev get deployment go-app -o jsonpath='{.status.readyReplicas}')" == 2 ]]; }
retry "deployment/go-app in go-app-dev has 2 ready replicas" two_ready

step "Steady state"
# Health can degrade after the first sync (e.g. an HPA that cannot read metrics): check every Application again.
app_ok() { [[ "$(k -n argocd get application "$1" -o jsonpath='{.status.sync.status}/{.status.health.status}')" == Synced/Healthy ]]; }
for app in $(k -n argocd get applications -o jsonpath='{.items[*].metadata.name}'); do
  retry "application $app is still Synced/Healthy" app_ok "$app"
done
hpa_active() { [[ "$(k -n go-app-prod get hpa go-app -o jsonpath='{.status.conditions[?(@.type=="ScalingActive")].status}')" == True ]]; }
retry "the prod HPA reads CPU metrics (ScalingActive)" hpa_active

printf '\n\033[32mEnd-to-end test passed.\033[0m\n'
