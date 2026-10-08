# Continuous integration

All workflows run on GitHub-hosted runners and call the same `make` targets a contributor runs locally.

| Workflow | Trigger | Jobs |
| --- | --- | --- |
| [`ci`](../.github/workflows/ci.yml) | pull request, push to `main` | **go**: gofmt, `go vet`, golangci-lint, unit tests with `-race` · **image**: hadolint, build, trivy vulnerability scan · **charts**: `helm lint`, helm-unittest, render + kubeconform · **shellcheck** · **trivy config** |
| [`e2e`](../.github/workflows/e2e.yml) | pull request, push to `main` | `make e2e`: kind + metrics-server, image built and loaded, commit under test pushed to an in-cluster Git server, Argo CD bootstrapped, smoke tests, self-heal, a Git change rolled out |
| [`release`](../.github/workflows/release.yml) | tag `vX.Y.Z` | checks the tag against the chart `appVersion`, builds `linux/amd64` + `linux/arm64`, pushes to `ghcr.io/hermeto/go-app` with provenance and SBOM |

The e2e workflow needs no secrets and pushes nothing: Argo CD reads the commit under test from a Git server running
inside the kind cluster ([`e2e/git-server.yaml`](../e2e/git-server.yaml)), so pull requests from forks are tested
the same way.

Workflows have read-only `contents` permission; only `release` gets `packages: write`, and only on tags.

## Why not a self-hosted runner

An earlier version of this repository documented a self-hosted runner on the developer's machine, so that CI could
reach a local cluster. It was removed:

- On a public repository, a pull request from a fork can run arbitrary code on a self-hosted runner — here, the
  developer's machine. GitHub [advises against it](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners#self-hosted-runner-security).
- It is no longer needed: CI creates its own cluster (kind) and Argo CD pulls from Git, so nothing has to push into
  the developer's cluster.

If self-hosted runners are ever required (private networks, GPUs), run them as ephemeral pods with
[Actions Runner Controller](https://github.com/actions/actions-runner-controller), which supports repository-level
runners for personal accounts as well as organizations, and restrict them to trusted workflows.

## Dependency updates

[Renovate](../renovate.json) opens pull requests for GitHub Actions (pinned to digests), Go, base images (Dockerfile,
pinned by digest), the Argo CD chart, the tool versions in the workflows and the images used by the tests. Each one
goes through `ci` and `e2e` like any other change.
