# go-app chart

Helm chart of the [go-app](../../app) service: Deployment, Service, ServiceAccount, and optionally a
HorizontalPodAutoscaler, a PodDisruptionBudget, a NetworkPolicy and an Ingress. Defaults are hardened and comply
with the `restricted` Pod Security Standard. Every value is validated by [`values.schema.json`](values.schema.json):
an unknown key, a wrong type or a mutable image tag (`latest`, `main`...) fails the render.

In this repository the chart is deployed by Argo CD, once per environment, with
[`environments/<env>/values.yaml`](../../environments). To install it by hand:

```bash
helm install go-app ./charts/go-app --namespace go-app --create-namespace
helm install go-app ./charts/go-app -f environments/prod/values.yaml   # with an environment's values
helm uninstall go-app --namespace go-app
```

With the release name `go-app`, resources are named `go-app`; with another release name, `<release>-go-app`.

## Values

| Key | Default | Description |
| --- | --- | --- |
| `image.repository` | `ghcr.io/hermeto/go-app` | Image repository. |
| `image.tag` | `""` (chart `appVersion`) | Immutable version tag. `latest`, `main`, `master`, `stable` and `edge` are rejected. |
| `image.digest` | `""` | `sha256:...`; takes precedence over the tag. |
| `image.pullPolicy` | `IfNotPresent` | |
| `imagePullSecrets` | `[]` | Pull secrets for a private registry. |
| `replicaCount` | `2` | Ignored when `autoscaling.enabled` (the HPA owns the replica count). |
| `containerPort` | `3000` | Passed to the app as `PORT`; the Service and the probes use the named port `http`. |
| `shutdown.delaySeconds` | `5` | Seconds the app keeps serving after SIGTERM with `/readyz` failing. |
| `shutdown.timeoutSeconds` | `20` | Seconds in-flight requests get to finish. Grace period = delay + timeout + 5. |
| `logLevel` | `info` | `debug`, `info`, `warn` or `error`. |
| `env` | `[]` | Extra environment variables (`PORT`, `SHUTDOWN_*`, `LOG_LEVEL`, `GOMEMLIMIT` are managed by the chart). |
| `serviceAccount.create` | `true` | Create a dedicated ServiceAccount. |
| `serviceAccount.name` | `""` | Name to use (default: full name, or `default` when not created). |
| `serviceAccount.annotations` | `{}` | E.g. workload identity bindings. |
| `serviceAccount.automountToken` | `false` | The app does not call the Kubernetes API. |
| `podAnnotations`, `podLabels` | `{}` | Extra pod metadata. |
| `podSecurityContext` | non-root 65532, `RuntimeDefault` seccomp | Pod security context. |
| `securityContext` | read-only root FS, no privilege escalation, drop `ALL` | Container security context. |
| `service.type` | `ClusterIP` | |
| `service.port` | `80` | |
| `service.annotations` | `{}` | |
| `ingress.enabled` | `false` | |
| `ingress.className` | `""` | |
| `ingress.annotations` | `{}` | |
| `ingress.hosts` | `go-app.local`, `/` | Hosts and paths routed to the Service. |
| `ingress.tls` | `[]` | |
| `resources` | requests 50m CPU / 32Mi, limit 32Mi | No CPU limit on purpose (throttling); `GOMEMLIMIT` follows the memory limit. |
| `startupProbe` | `GET /healthz`, 30 × 2s | An empty object disables a probe. |
| `livenessProbe` | `GET /healthz` every 10s | |
| `readinessProbe` | `GET /readyz` every 5s | |
| `autoscaling.enabled` | `false` | Create an HPA (requires metrics-server). |
| `autoscaling.minReplicas` / `maxReplicas` | `2` / `5` | `minReplicas` must not exceed `maxReplicas`. |
| `autoscaling.targetCPUUtilizationPercentage` | `80` | Requires `resources.requests.cpu`. |
| `autoscaling.targetMemoryUtilizationPercentage` | `null` | Requires `resources.requests.memory`. |
| `autoscaling.behavior` | `{}` | HPA scale-up/scale-down policies. |
| `podDisruptionBudget.enabled` | `true` | Evict one pod at a time during drains. |
| `podDisruptionBudget.maxUnavailable` | `1` | |
| `networkPolicy.enabled` | `true` | Ingress only on the HTTP port, egress only to cluster DNS. |
| `networkPolicy.ingressFrom` | `[]` | Allowed sources (NetworkPolicyPeer list); empty allows all. |
| `networkPolicy.extraEgress` | `[]` | Extra egress rules (databases, external APIs). |
| `topologySpreadConstraints` | soft spread across nodes | The pod selector is added automatically. |
| `revisionHistoryLimit` | `5` | |
| `nodeSelector`, `tolerations`, `affinity`, `priorityClassName` | empty | Scheduling. |
| `nameOverride`, `fullnameOverride` | `""` | Resource naming. |

## Tests

```bash
make helm-lint helm-unittest helm-render
```

[`tests/`](tests) holds the helm-unittest suites: hardening, naming, ports and probes, HPA/replica ownership,
schema rejections and the real environment values.

## Changes from 0.1.0

- Renamed from `app` to `go-app`; resource names no longer repeat the chart name (`go-app`, not `go-app-app`).
- Selector labels are `app.kubernetes.io/name` + `app.kubernetes.io/instance` (was `app`): **the Deployment must be
  recreated** — Argo CD does it when the old Application is replaced (see [operations](../../docs/operations.md)).
- `service.targetPort`, `livenessProbe.httpGet.port` and `readinessProbe.httpGet.port` are gone: the container
  port is `containerPort` and everything refers to it by name.
- `image.tag: latest` is rejected; the default tag is the chart `appVersion`.
- Autoscaling is off by default (enabled in `environments/prod`).
