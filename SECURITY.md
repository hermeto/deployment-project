# Security policy

## Reporting a vulnerability

Please do **not** open a public issue. Email hermeto.romano@gmail.com with a description and steps to reproduce.
You will get an answer within 7 days.

## Design

- **No credentials in the repository.** Argo CD reads this public repository anonymously; private repositories are
  registered as Kubernetes Secrets created outside Git ([docs/operations.md](docs/operations.md#private-repository)).
  CI uses the short-lived `GITHUB_TOKEN` only, with read-only permissions except `packages: write` when releasing.
- **Workloads** run under the `restricted` Pod Security Standard (enforced on the namespace), as a non-root user,
  with a read-only root filesystem, no capabilities, no service-account token, and a NetworkPolicy that only allows
  ingress on the HTTP port and egress to DNS. The image is distroless and pinned by digest at build time.
- **Argo CD** runs with an AppProject per concern: the `go-app` project can only deploy this repository into its
  own namespaces, and only an explicit list of resource kinds. The `default` project is disabled. `exec` from the UI
  is off. Rotate or disable the `admin` account on any shared cluster ([operations](docs/operations.md#secure-the-admin-account)).
- **Supply chain**: GitHub Actions and base images are pinned and updated by Renovate; images are published with
  provenance and an SBOM; `trivy` scans configuration and images in CI.

## Changes from earlier versions

Before 1.0.0 this repository documented a self-hosted GitHub Actions runner on the developer's machine. On a public
repository a fork's pull request can execute code on such a runner. It was removed in 1.0.0 in favour of
GitHub-hosted runners ([docs/ci.md](docs/ci.md#why-not-a-self-hosted-runner)). If you registered that runner,
remove it under *Settings → Actions → Runners* and delete its local directory.
