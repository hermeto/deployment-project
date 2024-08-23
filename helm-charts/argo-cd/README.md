# ArgoCD Local Deployment Guide

This guide will help you deploy ArgoCD on a local Kubernetes cluster using Helm, set up port-forwarding, and access the ArgoCD UI via localhost.

## Prerequisites

- A running Kubernetes cluster (Minikube, Kind, or any local Kubernetes setup).
- `kubectl` installed and configured to connect to your cluster.
- `Helm` installed.
- `Helmfile` installed.

## Steps

### 1. Install the ArgoCD Helm Chart

Install ArgoCD using the Helm chart in your local Kubernetes cluster.

```bash
cd helm-charts/argo-cd
helm repo add argo https://argoproj.github.io/argo-helm
helmfile init
helmfile apply
```

This command installs ArgoCD in the `argo-cd` namespace. You can customize the installation by editing the `values.yaml` file before running the install command.

### 2. Verify the Installation

Check that the ArgoCD pods are running.

```bash
kubectl get pods -n argo-cd
```

You should see output similar to:

```bash
NAME                                                        READY   STATUS    RESTARTS   AGE
argo-cd-argocd-application-controller-0                     1/1     Running   0          1m
argo-cd-argocd-applicationset-controller-594c9db87f-mgqcb   1/1     Running   0          1m
argo-cd-argocd-dex-server-79785757cf-6bhp9                  1/1     Running   0          1m
argo-cd-argocd-notifications-controller-6d54dfb6ff-8tknl    1/1     Running   0          1m
argo-cd-argocd-redis-6c74c6cbd6-qmbk9                       1/1     Running   0          1m
argo-cd-argocd-repo-server-c4486b764-gzv77                  1/1     Running   0          1m
argo-cd-argocd-server-7485456d86-vfxlm                      1/1     Running   0          1m
```

### 3. Set Up Port-Forwarding

To access the ArgoCD web UI locally, you need to set up port-forwarding.

```bash
kubectl port-forward svc/argo-cd-argocd-server -n argo-cd 8080:80
```

This command forwards port 8080 on your localhost to port 80 on the ArgoCD server service in your Kubernetes cluster.

### 4. Access the ArgoCD Web UI

With port-forwarding set up, you can now access the ArgoCD web UI by navigating to [http://localhost:8080](http://localhost:8080) in your web browser.

### 5. Retrieve the Admin Password

To log in to ArgoCD, you'll need the admin password. By default, the password is stored in a Kubernetes secret.

Retrieve the password with the following command:

```bash
kubectl get secret argocd-initial-admin-secret -n argo-cd -o jsonpath="{.data.password}" | base64 --decode
```

The output will be the password for the `admin` user.

### 6. Log In to ArgoCD

- **Username:** `admin`
- **Password:** The password you retrieved in the previous step.

After logging in, you can start using ArgoCD to manage your Kubernetes applications.

### Troubleshooting

- **Port-Forwarding Issues**: Ensure you have an active connection to your Kubernetes cluster and that no other process is using port 8080 on your localhost.
- **Pod Status**: If any ArgoCD pods are not running, check their logs using `kubectl logs` for more details.

### Cleanup

To uninstall ArgoCD from your cluster:

```bash
helm uninstall argo-cd -n argo-cd
kubectl delete namespace argo-cd
```

This will remove all ArgoCD components from your cluster.
