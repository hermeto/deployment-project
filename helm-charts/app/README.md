# App Helm Chart

This is a Helm chart for deploying a basic application on a Kubernetes cluster.

## Chart Structure

This Helm chart creates a Deployment for the basic application, configures a `ClusterIP` Service to expose the application internally within the cluster, and optionally sets up a Horizontal Pod Autoscaler (HPA).

## Installing the Chart

To install the chart with the release name `my-release`:

```bash
helm install my-release ./helm-charts/go-app
```

## Uninstalling the Chart

To uninstall the chart with the release name `my-release`:

```bash
helm uninstall my-release
```

This command removes all the components that were installed by the chart's release.

## Configurable Variables

Below is a table of all the configurable variables in the `values.yaml` of this chart.

| Parameter                                    | Description                                                              | Default Value                     |
|----------------------------------------------|--------------------------------------------------------------------------|-----------------------------------|
| `replicaCount`                               | Number of replicas for the Deployment                                    | `2`                               |
| `image.repository`                           | Container image repository                                                  | `registry/go-app`             |
| `image.tag`                                  | Container image tag                                                         | `latest`                          |
| `image.pullPolicy`                           | Container image pull policy                                                 | `IfNotPresent`                    |
| `service.type`                               | Kubernetes Service type                                                  | `ClusterIP`                       |
| `service.port`                               | Service port                                                             | `80`                              |
| `resources.requests.cpu`                     | CPU resource request per pod                                             | `100m`                            |
| `resources.requests.memory`                  | Memory resource request per pod                                          | `64Mi`                            |
| `resources.limits.cpu`                       | CPU resource limit per pod                                               | `100m`                            |
| `resources.limits.memory`                    | Memory resource limit per pod                                            | `128Mi`                           |
| `autoscaling.enabled`                        | Enable Horizontal Pod Autoscaler                                         | `true`                            |
| `autoscaling.minReplicas`                    | Minimum number of replicas for HPA                                       | `1`                               |
| `autoscaling.maxReplicas`                    | Maximum number of replicas for HPA                                       | `5`                               |
| `autoscaling.targetCPUUtilizationPercentage` | Target CPU utilization percentage for HPA                                | `80`                              |
| `nodeSelector`                               | Node labels for pod assignment                                           | `{}`                              |
| `tolerations`                                | Tolerations for pod assignment                                           | `[]`                              |
| `affinity`                                   | Affinity for pod assignment                                              | `{}`                              |
| `livenessProbe.httpGet.path`                 | HTTP path for liveness probe                                             | `/healthz`                        |
| `livenessProbe.httpGet.port`                 | Port for liveness probe                                                  | `8080`                            |
| `livenessProbe.initialDelaySeconds`          | Initial delay before the first execution of the liveness probe           | `10`                              |
| `livenessProbe.periodSeconds`                | Time interval between liveness probe executions                          | `10`                              |
| `livenessProbe.timeoutSeconds`               | Timeout for the liveness probe                                           | `5`                               |
| `livenessProbe.failureThreshold`             | Number of consecutive liveness probe failures before marking pod as unhealthy | `3`           |
| `readinessProbe.httpGet.path`                | HTTP path for readiness probe                                            | `/readyz`                         |
| `readinessProbe.httpGet.port`                | Port for readiness probe                                                 | `8080`                            |
| `readinessProbe.initialDelaySeconds`         | Initial delay before the first execution of the readiness probe          | `5`                               |
| `readinessProbe.periodSeconds`               | Time interval between readiness probe executions                         | `10`                              |
| `readinessProbe.timeoutSeconds`              | Timeout for the readiness probe                                          | `5`                               |
| `readinessProbe.failureThreshold`            | Number of consecutive readiness probe failures before marking pod as unhealthy | `3`        |
