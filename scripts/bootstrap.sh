#!/usr/bin/env bash
# Bootstraps GitOps on a cluster: installs Argo CD with Helm, then applies the AppProjects and the `root`
# Application. From then on Argo CD deploys everything else from Git, including its own upgrades.
#
# Bootstrapping is a one-time operation: when the `argocd` Helm release already exists, the install step is
# skipped (Argo CD manages itself afterwards) unless FORCE_INSTALL=true.
#
# Usage: scripts/bootstrap.sh <argo-cd chart directory>
# Environment:
#   KUBE_CONTEXT     kubeconfig context (default: current context)
#   REPO_URL         Git repository Argo CD tracks (default: repo.url in gitops/root/values.yaml)
#   REPO_REVISION    branch, tag or commit to track (default: repo.revision in gitops/root/values.yaml)
#   TIMEOUT          seconds to wait for Argo CD to become ready (default: 600)
#   FORCE_INSTALL    re-run `helm upgrade --install` even if Argo CD is already installed (default: false)
set -euo pipefail

cd "$(dirname "$0")/.."

chart_dir="${1:?usage: $0 <argo-cd chart directory>}"
namespace=argocd
timeout="${TIMEOUT:-600}"

# Written for bash 3.2 (macOS) too: no mapfile, no empty arrays under `set -u`.
k() { if [[ -n "${KUBE_CONTEXT:-}" ]]; then kubectl --context "$KUBE_CONTEXT" "$@"; else kubectl "$@"; fi; }
h() { if [[ -n "${KUBE_CONTEXT:-}" ]]; then helm --kube-context "$KUBE_CONTEXT" "$@"; else helm "$@"; fi; }

repo_url="${REPO_URL:-$(awk '/^repo:/{f=1} f && /url:/{print $2; exit}' gitops/root/values.yaml)}"
repo_revision="${REPO_REVISION:-$(awk '/^repo:/{f=1} f && /revision:/{print $2; exit}' gitops/root/values.yaml)}"

echo "==> Argo CD"
if h status argocd --namespace "$namespace" >/dev/null 2>&1 && [[ "${FORCE_INSTALL:-false}" != "true" ]]; then
  echo "    release argocd already installed: Argo CD manages itself, skipping (FORCE_INSTALL=true to reinstall)"
else
  h upgrade --install argocd "$chart_dir" \
    --namespace "$namespace" --create-namespace \
    --values gitops/argocd/values.yaml \
    --wait --timeout "${timeout}s"
fi
k -n "$namespace" rollout status deployment/argocd-server --timeout="${timeout}s"
k -n "$namespace" rollout status deployment/argocd-repo-server --timeout="${timeout}s"
k -n "$namespace" rollout status statefulset/argocd-application-controller --timeout="${timeout}s"

echo "==> AppProjects and root Application ($repo_url @ $repo_revision)"
helm template root gitops/root --namespace "$namespace" \
  --set-string "repo.url=$repo_url" --set-string "repo.revision=$repo_revision" \
  --show-only templates/projects.yaml --show-only templates/root.yaml |
  k apply -f -

cat <<EOF

Argo CD is now syncing the repository. Follow it with:
  kubectl -n $namespace get applications -w
UI: make argocd-ui
EOF
