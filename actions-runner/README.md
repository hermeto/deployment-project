# Self-Hosted GitHub Actions Runner Setup

## Overview

This repository includes a self-hosted GitHub Actions runner to facilitate the continuous integration and deployment (CI/CD) process entirely within a local environment. Due to the nature of this project, where the entire stack is designed to run locally, a self-hosted runner was added to ensure all components operate within the same environment.

### Limitations

It’s important to note that deploying the GitHub Actions runner via Kubernetes was not pursued due to limitations within GitHub's architecture. Specifically, running self-hosted runners on Kubernetes in a non-organization account is restricted. To deploy a GitHub Actions runner on Kubernetes, you must have an organization account. This project is based on a personal account, which does not support such a configuration.

## Setup Instructions

Follow the steps below to configure and start your self-hosted GitHub Actions runner.

### 1. Download and Install the Runner

1. **Enter the directory:**

    ```bash
    cd actions-runner
    ```

2. **Follow the documentation below to set up the runner locally according to your operating system:**

    https://github.com/<your-username\>/deployment-project/settings/actions/runners/new

## Additional Information

For further details on configuring, running, or shutting down the runner, please check out the [official GitHub documentation](https://docs.github.com/en/actions/hosting-your-own-runners).
