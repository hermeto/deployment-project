# Go App Deployment Project

## Overview

This project contains the necessary configuration to deploy a Go application in a Kubernetes cluster using ArgoCD and Helm. The project follows a monorepo structure to simplify the deployment process, allowing for centralized management of all related components, including the application code, Helm charts, and infrastructure configuration.

## Monorepo Structure

The project is organized as a monorepo, which means that all related code, configuration files, and scripts are stored in a single repository. This approach was chosen to simplify the development and deployment process, particularly for this test scenario where simplicity and clarity are key requirements.

### Project Structure

```plaintext
.
├── README.md                             # Root project documentation
├── argo-cd                               # ArgoCD configuration directory
│   └── applications                      # Directory for ArgoCD Application manifests
│       ├── README.md                     # Documentation for ArgoCD applications
│       └── go-app.yaml                   # ArgoCD Application manifest for the Go app
└── helm-charts                           # Directory for Helm charts
    ├── app                               # Helm chart for the Go application
    │   ├── Chart.yaml                    # Metadata for the Go app Helm chart
    │   ├── README.md                     # Documentation for the Go app Helm chart
    │   ├── templates                     # Directory for Kubernetes resource templates
    │   │   ├── _helpers.tpl              # Helper template functions
    │   │   ├── deployment.yaml           # Deployment resource template
    │   │   ├── hpa.yaml                  # Horizontal Pod Autoscaler (HPA) resource template
    │   │   └── service.yaml              # Service resource template
    │   └── values.yaml                   # Default configuration values for the Go app
    └── argo-cd                           # Helm chart for ArgoCD configuration
        ├── Chart.yaml                    # Metadata for the ArgoCD Helm chart
        ├── README.md                     # Documentation for the ArgoCD Helm chart
        ├── helmfile.yaml                 # Helmfile for managing ArgoCD installation
        └── values.yaml                   # Default configuration values for ArgoCD
```

### Why Monorepo?

- **Simplicity**: By keeping all related files in one place, the complexity of managing multiple repositories is avoided, making the setup easier to understand and use.
- **Consistency**: Changes to the application, infrastructure, or deployment configuration can be synchronized and tested together, reducing the risk of inconsistencies.
- **Single Source of Truth**: All components related to the deployment are centralized, providing a clear view of the entire deployment pipeline.

## Trade-offs

While the monorepo approach has several advantages, there are also trade-offs to consider:

### Pros

1. **Ease of Use**: All necessary components are in one place, reducing the need to navigate between different repositories.
2. **Coordinated Changes**: Updates to the application, infrastructure, and CI/CD pipeline can be managed together, reducing the chance of mismatches or missed updates.
3. **Simplified Versioning**: A single version control history ensures that all changes are tracked together, simplifying the process of rolling back or auditing changes.

### Cons

1. **Scalability**: As the project grows, the monorepo can become harder to manage, especially if the number of services, microservices, or infrastructure components increases significantly.
2. **Longer CI/CD Pipelines**: Changes to any part of the monorepo may trigger the CI/CD pipeline, even if the change is unrelated to certain components. This can lead to longer build times.
3. **Potential for Merge Conflicts**: With multiple developers working in the same repository, the likelihood of merge conflicts can increase, particularly if many files are being modified simultaneously.

## Future Improvements

As the project evolves, there are several enhancements that could be considered:

### 1. **Modularization**

- **Sub-repos or Git Submodules**: As the project grows, consider splitting the monorepo into smaller, more manageable sub-repositories or using Git submodules to maintain modularity while still benefiting from a monorepo-like structure.

### 2. **Improved CI/CD Efficiency**

- **Selective Builds**: Implement logic in the CI/CD pipeline to trigger builds only for the parts of the project that have been modified. This can reduce build times and resource consumption.
- **Pipeline Parallelization**: Parallelize different stages of the CI/CD pipeline to speed up deployments, particularly when handling multiple services or components.

### 3. **Advanced Infrastructure Management**

- **Infrastructure as Code (IaC)**: As the infrastructure grows, consider introducing more advanced IaC tools (e.g., Terraform, Pulumi) to manage infrastructure changes in a more scalable and repeatable manner.
- **Environment-Specific Configurations**: Introduce environment-specific Helm values files (e.g., for staging, production) to allow for more granular control over how the application is deployed in different environments.

### 4. **Monitoring and Alerts**

- **Integrate Monitoring**: Add monitoring tools (e.g., Prometheus, Grafana) to keep track of application performance and resource usage.
- **Set Up Alerts**: Configure alerting mechanisms to notify the team of any issues or anomalies in the application or infrastructure.

## Documentation Overview

This project includes documentation files to help you understand and work with the different components. Below is a list of the key documentation files available within the project, organized by directory.

### 1. [ArgoCD Helm Chart](./helm-charts/argo-cd/README.md)

### 2. [ArgoCD Go Application](./argo-cd/applications/README.md)

### 3. [Self-Hosted GitHub Actions Runner Setup](./actions-runner/README.md)

### 4. [Application Helm Chart](./helm-charts/app/README.md)

