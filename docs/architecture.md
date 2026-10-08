# Architecture

## Components

| Component | Path | Role |
| --- | --- | --- |
| go-app | [`app/`](../app) | Go HTTP service. Standard library only; JSON logs; `/healthz` (liveness), `/readyz` (readiness), graceful shutdown. Image: static binary on `distroless/static:nonroot`. |
| go-app chart | [`charts/go-app/`](../charts/go-app) | How the service runs on Kubernetes. Hardened defaults, values validated by `values.schema.json`. |
| Environments | [`environments/`](../environments) | One values file per environment, merged over the chart defaults. |
| Argo CD values | [`gitops/argocd/values.yaml`](../gitops/argocd/values.yaml) | Configuration of Argo CD (argo-cd Helm chart). |
| Root chart | [`gitops/root/`](../gitops/root) | App of apps: renders the AppProjects and Applications Argo CD syncs. |

## The GitOps tree

```text
root (Application, project: platform)          gitops/root, renders itself and:
├── AppProject platform                          Argo CD + root; may create cluster-scoped resources
├── AppProject go-app                            this repository only; go-app-* namespaces only; explicit kind allow-list
├── AppProject default                           locked down: no sources, no destinations
├── argocd (Application, project: platform)      argo-cd chart (pinned) + gitops/argocd/values.yaml
├── go-app-dev (Application, project: go-app)    charts/go-app + environments/dev/values.yaml  -> namespace go-app-dev
└── go-app-prod (Application, project: go-app)   charts/go-app + environments/prod/values.yaml -> namespace go-app-prod
```

- **The root manages itself.** Its spec is rendered by the chart it points at, so changing the GitOps tree is a
  pull request like any other. Only the repository URL and revision are passed down through `valuesObject`; that is
  what lets the e2e test point the whole tree at an in-cluster Git server.
- **Argo CD manages itself.** `make bootstrap` installs the same chart version with the same values file once; the
  `argocd` Application then adopts the Helm release (server-side apply, no pod restart) and upgrades come from Git.
  It never prunes automatically and has no resources finalizer, so a mistake cannot delete Argo CD.
- **Workload Applications clean up after themselves.** `go-app-*` carry the resources finalizer and sync with
  `prune` and `selfHeal`: removing an environment from `goApp.environments` deletes its workload, and manual changes
  in the cluster are reverted.
- **Least privilege per project.** The `go-app` project can only deploy from this repository, only into its
  namespaces, and only Deployments, Services, ServiceAccounts, HPAs, PDBs, NetworkPolicies and Ingresses (plus the
  Namespace it creates). A chart change that adds a Role or a ClusterRole fails to sync until the project allows it.

## Workload hardening

| Control | Where |
| --- | --- |
| `restricted` Pod Security Standard enforced (`enforce`, `warn`, `audit`) on every application namespace | `managedNamespaceMetadata` of each go-app Application |
| Non-root UID 65532, read-only root filesystem, all capabilities dropped, no privilege escalation, `RuntimeDefault` seccomp | chart `podSecurityContext` / `securityContext` |
| No service-account token mounted, no service links | chart `serviceAccount.automountToken`, `enableServiceLinks: false` |
| Ingress only on the HTTP port; egress only to cluster DNS | chart `networkPolicy` |
| Immutable image references: mutable tags (`latest`, `main`...) rejected, digests supported | `values.schema.json` |
| Image: distroless, no shell, no package manager; base images pinned by digest | `app/Dockerfile` |

## Availability

- **Probes** — a startup probe protects slow starts; liveness restarts a hung process; readiness removes a pod from
  the Service while it starts or shuts down. All use the named port `http`, so changing `containerPort` cannot
  desynchronize them (the original chart hard-coded 8080 while the application listened on 3000).
- **Graceful shutdown** — on SIGTERM the service fails `/readyz` and keeps serving for `shutdown.delaySeconds`
  while endpoints are updated, then gives in-flight requests `shutdown.timeoutSeconds`.
  `terminationGracePeriodSeconds` is derived from both.
- **Rollouts** — `maxUnavailable: 0`: capacity never drops during a deployment.
- **Scaling** — with `autoscaling.enabled`, the Deployment has no `replicas` field: the HPA owns it, so Argo CD
  self-heal and the HPA never fight (in the original setup self-heal reset the replica count on every sync).
  The HPA needs metrics-server (managed clusters ship it; `make local-up` installs it on kind).
- **Disruptions** — a PodDisruptionBudget (`maxUnavailable: 1`, `unhealthyPodEvictionPolicy: AlwaysAllow`) and a
  soft topology spread across nodes.

## Environments

`dev` and `prod` run on the same cluster in separate namespaces, which keeps the project runnable on a laptop. To
target separate clusters, register them in Argo CD (`argocd cluster add`) and give each environment its own
destination: extend `goApp.environments` with a `server` field and use it in
[`gitops/root/templates/go-app.yaml`](../gitops/root/templates/go-app.yaml) and in the `go-app` AppProject
destinations.

## Why a monorepo

The application, its chart, the environments and the GitOps configuration live in one repository.

**Pros**

- One pull request can change the code, the chart and the configuration together, and CI tests them together:
  the e2e test deploys exactly the commit under review.
- One history to audit and roll back.
- Simple to understand and to run locally.

**Cons**

- Releasing the application and changing the deployment share one permission model: anyone who can merge can
  deploy. Branch protection and CODEOWNERS mitigate it.
- CI runs for every change. The jobs are independent and fast; path filters can be added as the repository grows.
- Argo CD polls this repository for every Application; with many services, a dedicated configuration repository
  (and image promotion by pull request from the application repositories) scales better.

## Possible next steps

- SSO for Argo CD (OIDC or Dex) and `admin.enabled: false`; RBAC per team.
- An Ingress or Gateway in front of the Argo CD UI and the service, with real certificates (cert-manager).
- Image promotion automation (Argo CD Image Updater or a workflow that opens the tag-bump pull request).
- Image signing (cosign) and admission-time verification.
- ServiceMonitor and alerts for go-app once the cluster runs a Prometheus Operator.
