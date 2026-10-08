# GitOps workflow

Git is the source of truth. After the one-time bootstrap, every change to the cluster is a commit on `main`:
Argo CD polls the repository (every ~3 minutes, or immediately on a refresh) and converges the cluster on it.

## Applications

The [root chart](../gitops/root) renders one Application per environment:

```yaml
# gitops/root/values.yaml
goApp:
  chartPath: charts/go-app
  environments:
    - name: dev
      namespace: go-app-dev
    - name: prod
      namespace: go-app-prod
```

Each `go-app-<env>` Application deploys [`charts/go-app`](../charts/go-app) with
`environments/<env>/values.yaml`, in the namespace `go-app-<env>`, with:

| Setting | Effect |
| --- | --- |
| `automated.selfHeal: true` | Manual changes in the cluster are reverted. |
| `automated.prune: true` | Resources removed from Git are deleted. |
| `CreateNamespace=true` + `managedNamespaceMetadata` | Argo CD creates the namespace with the `restricted` Pod Security labels. |
| `PruneLast=true` | Old resources are pruned only after the new ones are healthy. |
| `retry` | Failed syncs are retried with exponential backoff (10s → 3m, 5 attempts). |
| resources finalizer | Deleting the Application (or removing the environment from Git) deletes its workload. |

## Delivering a new version

1. Merge the code change.
2. Bump `appVersion` in [`charts/go-app/Chart.yaml`](../charts/go-app/Chart.yaml) and add a CHANGELOG entry.
3. Tag the release: `git tag v1.1.0 && git push origin v1.1.0`. The [release workflow](../.github/workflows/release.yml)
   checks that the tag matches `appVersion` and publishes `ghcr.io/hermeto/go-app:1.1.0` (amd64 and arm64, with
   provenance and SBOM).
4. Deploy to dev: pull request setting `image.tag: "1.1.0"` in
   [`environments/dev/values.yaml`](../environments/dev/values.yaml). After the merge, Argo CD rolls it out.
5. Promote to prod: the same change in [`environments/prod/values.yaml`](../environments/prod/values.yaml).

For stronger guarantees, pin `image.digest` instead of the tag (the digest is printed by the release workflow).

## Rolling back

Revert the commit (`git revert <sha>` and merge). Argo CD syncs the previous state. Rolling back from the Argo CD UI
works too, but only while automated sync is disabled for that Application — otherwise the next sync re-applies
Git; prefer the revert.

## Adding an environment

1. Create `environments/<name>/values.yaml` (copy `dev` or `prod`).
2. Add `{name: <name>, namespace: go-app-<name>}` to `goApp.environments` in
   [`gitops/root/values.yaml`](../gitops/root/values.yaml).
3. Merge. The root Application creates `go-app-<name>`, the `go-app` AppProject allows the new namespace, and the
   new Application deploys it.

Removing the entry deletes the Application and, through its finalizer, the workload.

## Changing Argo CD

- Configuration: [`gitops/argocd/values.yaml`](../gitops/argocd/values.yaml).
- Version: `argocd.chart.version` in [`gitops/root/values.yaml`](../gitops/root/values.yaml). Read the upgrade notes
  of the [argo-cd chart](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd#upgrading) first; `make
  helm-render` validates the new chart with our values and the e2e test installs it.
