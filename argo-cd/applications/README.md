# ArgoCD Application Configuration for Go App

This document explains how to use the provided `go-app.yaml` file to deploy and manage a Go application using ArgoCD in a Kubernetes cluster.

## Overview

The `go-app.yaml` file defines an ArgoCD Application resource that will manage the deployment of your Go application. It utilizes a Helm chart located in a Git repository, ensuring that your application is always in sync with the desired state defined in your version control system.

## Prerequisites

Before applying the `go-app.yaml`, ensure the following prerequisites are met:

1. **Kubernetes Cluster**: You have access to a running Kubernetes cluster.
2. **ArgoCD Installed**: ArgoCD is installed and running in your Kubernetes cluster.

## Structure of `application.yaml`

- **`metadata`**: Defines the name and namespace of the ArgoCD Application.
- **`spec.source`**: Specifies the source of the Helm chart, including the Git repository URL, the branch or tag to monitor, and the path to the chart within the repository.
- **`spec.destination`**: Specifies the Kubernetes cluster and namespace where the application should be deployed.
- **`spec.syncPolicy`**: Configures how ArgoCD syncs the application state with the cluster, including automated syncing and self-healing.

## Applying the Configuration

Apply the `go-app.yaml` file using `kubectl`:

```bash
cd argo-cd/applications
kubectl apply -f go-app.yaml -n argo-cd
```

This command will create the ArgoCD Application resource, and ArgoCD will begin managing the deployment of your Go application based on the configuration provided.

## Syncing and Managing the Application

Once the `go-app.yaml` is applied, ArgoCD will:

- Monitor the specified Git repository for changes.
- Automatically apply updates to the Kubernetes cluster when changes are detected.
- Ensure the application remains in sync with the desired state defined in the Helm chart.

You can manage and monitor the application using the ArgoCD web UI, CLI, or API.

## Customization

The `go-app.yaml` includes several parameters that can be customized:

- **Replica Count**: Control the number of replicas of your application.
- **Image Repository and Tag**: Specify the Docker image to use for your application.
- **Service Port**: Configure the port on which your application will be exposed within the cluster.
- **Auto-scaling**: Enable or disable the Horizontal Pod Autoscaler (HPA) and configure its behavior.

These parameters can be adjusted directly within the `go-app.yaml` under the `parameters` section.

## Troubleshooting

If you encounter issues with the deployment:

- **Check ArgoCD Logs**: Use the ArgoCD UI or CLI to check the logs for any errors.
- **Verify Namespace and Access**: Ensure the namespace specified in `go-app.yaml` exists and that ArgoCD has the necessary permissions to deploy applications there.
- **Sync Issues**: If the application does not sync as expected, manually trigger a sync from the ArgoCD UI or CLI.

## Conclusion

The `go-app.yaml` provides a robust and flexible way to manage the deployment of your Go application using ArgoCD and Helm. By leveraging GitOps principles, you ensure that your application's desired state is always maintained and versioned in your Git repository.
