# Contributing

## Workflow

1. Create a branch from `main`.
2. Install the hooks once: `pre-commit install` ([pre-commit](https://pre-commit.com/)).
3. Make the change, then run the checks CI runs:

   ```bash
   make check   # Go fmt/vet/lint/tests, hadolint, helm lint + unittest + render/kubeconform, shellcheck, trivy
   make e2e     # optional locally, always in CI: kind + Argo CD + the whole GitOps tree + end-to-end tests
   ```

4. Open a pull request. Both the `ci` and `e2e` workflows must pass.

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`,
`chore:`...). Add a line to [CHANGELOG.md](CHANGELOG.md) under *Unreleased* for user-visible changes.

## Conventions

- **Application** (`app/`): standard library unless a dependency clearly pays for itself; every behaviour has a
  test in `server_test.go`; configuration only through environment variables documented in `loadConfig`.
- **Chart** (`charts/go-app/`): every new value goes into `values.yaml` (with a `# --` description),
  `values.schema.json` and the table in the chart README, and gets a helm-unittest case. Bump the chart `version`
  on every chart change.
- **GitOps** (`gitops/`): a new kind of resource in the chart must be allowed explicitly in the `go-app` AppProject
  (`gitops/root/templates/projects.yaml`). Never add `kubectl apply` steps outside the bootstrap.
- **Environments**: pin images by version tag or digest, never by a mutable tag (the schema rejects them).
- **Scripts**: `set -euo pipefail`, shellcheck-clean, compatible with bash 3.2 (macOS).
- **Secrets**: never commit credentials or kubeconfigs. `gitleaks` runs in pre-commit.

## Releasing

See [docs/gitops.md](docs/gitops.md#delivering-a-new-version): bump `appVersion`, tag `vX.Y.Z`, then promote the
tag through `environments/`.
