# Self-Hosted GitHub Actions Runner Setup

## Overview

This repository includes a self-hosted GitHub Actions runner to facilitate the continuous integration and deployment (CI/CD) process entirely within a local environment. Due to the nature of this project, where the entire stack is designed to run locally, a self-hosted runner was added to ensure all components operate within the same environment.

### Limitations

It’s important to note that deploying the GitHub Actions runner via Kubernetes was not pursued due to limitations within GitHub's architecture. Specifically, running self-hosted runners on Kubernetes in a non-organization account is restricted. To deploy a GitHub Actions runner on Kubernetes, you must have an organization account. This project is based on a personal account, which does not support such a configuration.

## Setup Instructions

Follow the steps below to configure and start your self-hosted GitHub Actions runner.

### 1. Download and Install the Runner

1. **Create a folder for the runner:**

    ```bash
    cd actions-runner
    mkdir runner && cd runner
    ```

2. **Download the latest runner package:**

    ```bash
    curl -o actions-runner-osx-arm64-2.319.1.tar.gz -L https://github.com/actions/runner/releases/download/v2.319.1/actions-runner-osx-arm64-2.319.1.tar.gz
    ```

3. **(Optional) Validate the download:**

    ```bash
    echo "af6a2fba35cc63415693ebfb969b4d7a9d59158e1f3587daf498d0df534bf56f  actions-runner-osx-arm64-2.319.1.tar.gz" | shasum -a 256 -c
    ```

4. **Extract the installer:**

    ```bash
    tar xzf ./actions-runner-osx-arm64-2.319.1.tar.gz
    ```

### 2. Configure the Runner

1. **Create the runner and start the configuration:**

    ```bash
    ./config.sh --url https://github.com/<your-username>/p2p-devops-test --token <your-token>
    ```

2. **Start the runner:**

    ```bash
    ./run.sh
    ```

### 3. Using Your Self-Hosted Runner

Add the following to your GitHub Actions workflow YAML to ensure that jobs run on this self-hosted runner:

```yaml
runs-on: self-hosted
```

## Additional Information

For further details on configuring, running, or shutting down the runner, please check out the [official GitHub documentation](https://docs.github.com/en/actions/hosting-your-own-runners).
