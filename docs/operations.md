# Operations

All commands take `KUBE_CONTEXT=<context>` (default: `kind-gitops`).

## Bootstrap a cluster

```bash
make bootstrap KUBE_CONTEXT=<context>
```

[`scripts/bootstrap.sh`](../scripts/bootstrap.sh):

1. installs the pinned argo-cd chart (release `argocd`, namespace `argocd`) with
   [`gitops/argocd/values.yaml`](../gitops/argocd/values.yaml) — skipped when the release already exists, because
   Argo CD manages itself afterwards (`FORCE_INSTALL=true` to reinstall);
2. applies the AppProjects and the `root` Application. Argo CD then creates everything else.

`REPO_URL` and `REPO_REVISION` override the tracked repository and branch (for a fork, change `repo.url` in
[`gitops/root/values.yaml`](../gitops/root/values.yaml) instead, so that the setting lives in Git).

### Private repository

Register the credentials before the bootstrap, as a labelled Secret (never commit it):

```bash
kubectl create namespace argocd
kubectl -n argocd create secret generic repo-deployment-project \
  --from-literal=type=git \
  --from-literal=url=https://github.com/<owner>/deployment-project.git \
  --from-literal=username=x-access-token \
  --from-literal=password=<fine-grained token with read access to contents>
kubectl -n argocd label secret repo-deployment-project argocd.argoproj.io/secret-type=repository
```

A GitHub App or a deploy key is preferable to a personal token for long-lived clusters.

### Image pull

The environments use `ghcr.io/hermeto/go-app`. New GHCR packages are private: make the package public
(*Package settings → Change visibility*) or create a pull secret in each namespace and reference it with
`imagePullSecrets` in `environments/<env>/values.yaml`.

## Access the Argo CD UI

```bash
make argocd-ui KUBE_CONTEXT=<context>   # prints the admin password, then https://localhost:8080
```

The certificate is self-signed. With the `argocd` CLI:

```bash
argocd login localhost:8080 --username admin --insecure
argocd app list
```

### Secure the admin account

The initial password is random and stored in `argocd-initial-admin-secret`. On anything but a throwaway cluster:

```bash
argocd account update-password
kubectl -n argocd delete secret argocd-initial-admin-secret
```

Better: configure SSO (`configs.cm.oidc.config` or Dex in `gitops/argocd/values.yaml`), grant roles in
`configs.rbac`, and set `configs.cm.admin.enabled: false`.

## Day-to-day

| Task | Command |
| --- | --- |
| Status of every Application | `kubectl -n argocd get applications` |
| Why an Application is OutOfSync/Degraded | `kubectl -n argocd describe application go-app-prod` (conditions, resources) or the UI |
| Sync now instead of waiting for the poll | `kubectl -n argocd annotate application go-app-dev argocd.argoproj.io/refresh=normal --overwrite` |
| Check a deployment end to end | `make smoke KUBE_CONTEXT=<context>` |
| Reach the service | `kubectl -n go-app-dev port-forward svc/go-app 8080:80` then `curl localhost:8080/` |
| Logs | `kubectl -n go-app-prod logs deployment/go-app` (JSON, one line per request) |

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `go-app-*` is `Degraded`, the HPA says `FailedGetResourceMetric` | metrics-server is missing (`make metrics-server` on kind). |
| Pods in `ImagePullBackOff` | The tag does not exist in GHCR (tag a release first) or the package is private. |
| Sync fails with `... is not permitted in project go-app` | The chart renders a kind or namespace the `go-app` AppProject does not allow: extend `gitops/root/templates/projects.yaml` deliberately. |
| Sync fails with `violates PodSecurity "restricted"` | A value weakened the security context; the namespace enforces the restricted standard. |
| `root` is `ComparisonError` | The root chart does not render: run `make helm-unittest helm-render` locally. |
| A manual change disappeared | Self-heal: change Git instead. |

## Upgrade Argo CD

Bump `argocd.chart.version` in `gitops/root/values.yaml` (Renovate opens the pull request), check the
[chart upgrade notes](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd#upgrading), let CI run
`helm-render` and the e2e test, merge. The `argocd` Application applies the new version.

## Uninstall

```bash
# root first (no finalizer: it leaves its children in place), otherwise self-heal recreates what you delete.
kubectl -n argocd delete application root
# Workloads: the resources finalizer deletes what each Application deployed.
kubectl -n argocd delete application go-app-dev go-app-prod
kubectl -n argocd delete application argocd          # no finalizer: Argo CD itself stays
helm uninstall argocd -n argocd
kubectl delete namespace argocd go-app-dev go-app-prod
# The CRDs are kept on purpose (crds.keep); delete them only if no Argo CD is left in the cluster:
kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io
```

## Migrating from the pre-1.0 layout

The previous layout installed Argo CD in the `argo-cd` namespace with helmfile and deployed a single `go-app`
Application (tracking another repository) into `go-app`. On a cluster that still runs it:

```bash
kubectl -n argo-cd delete application go-app        # remove the old Application and its resources
helm uninstall argo-cd -n argo-cd
kubectl delete namespace argo-cd go-app
make bootstrap KUBE_CONTEXT=<context>
```
