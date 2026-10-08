# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-10-08

Complete rewrite. Not compatible with the previous layout: see the migration steps in
[docs/operations.md](docs/operations.md#migrating-from-the-pre-10-layout).

### Added

- Go service (`app/`) with `/healthz`, `/readyz`, graceful shutdown, unit tests and a distroless, non-root image.
- `go-app` chart: JSON schema for the values, named port, startup probe, ServiceAccount, PodDisruptionBudget,
  NetworkPolicy, topology spreading, optional Ingress, `GOMEMLIMIT`, restricted security contexts.
- App of apps (`gitops/root`): AppProjects (`platform`, `go-app`, `default` locked down), self-managed Argo CD and
  one Application per environment (`dev`, `prod`) with self-heal, pruning, retries and the restricted Pod Security
  Standard enforced on the namespaces.
- `make check` (Go, hadolint, helm lint, helm-unittest, render + kubeconform, shellcheck, trivy) and `make e2e`
  (kind + metrics-server + Argo CD + in-cluster Git server + smoke tests + self-heal + a Git change rolled out),
  both in GitHub Actions; `release` workflow publishing multi-arch images to GHCR with provenance and SBOM.
- Renovate, pre-commit hooks, architecture, GitOps workflow, operations and CI documentation.

### Changed

- Argo CD 2.12 with an unpinned chart, installed by helmfile into `argo-cd` → argo-cd chart 10.10.0 (Argo CD 3.5)
  pinned in Git, installed once by `make bootstrap` into `argocd`, then managed by Argo CD itself.
- The Application tracked another repository (`p2p-eigen-layer`); every Application now tracks this repository.
- One `go-app` Application in namespace `go-app` → `go-app-dev` and `go-app-prod` with per-environment values,
  instead of Helm parameters inlined in the Application.
- `hermeto/go-app:latest` from Docker Hub → `ghcr.io/hermeto/go-app` pinned by version; mutable tags are rejected.
- Chart `app` → `go-app` 1.0.0: selector labels, naming and ports changed (see the chart README).

### Fixed

- The container port was hard-coded to 8080 while the application listens on 3000 and the probes were overridden
  to 3000 in the Application: the port is now defined once.
- With autoscaling enabled, `replicas` was still rendered, so Argo CD self-heal reset the replica count chosen by
  the HPA on every sync.
- `latest` with `IfNotPresent` meant new versions were never pulled and never visible to Argo CD.
- Two releases in one namespace selected each other's pods (selector was only `app: <chart name>`).
- `image.pullPolicy` was ignored; `replicaCount` in the Argo CD values was not a valid key.
- Documentation pointed to non-existent paths (`helm-charts/go-app`, `application.yaml`).

### Removed

- Self-hosted GitHub Actions runner instructions (`actions-runner/`): a security risk on a public repository.
- helmfile and the local `argo-cd` wrapper chart.

## [0.1.0] - 2024-09-03

- Initial Argo CD + Helm deployment of the Go application.
