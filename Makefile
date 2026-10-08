SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help
MAKEFLAGS += --no-print-directory

# ----------------------------------------------------------------------------
# Settings (override on the command line: make e2e KIND_CLUSTER=foo)
# ----------------------------------------------------------------------------
KIND_CLUSTER        ?= gitops
KIND_CONFIG         ?= kind/cluster.yaml
KUBE_CONTEXT        ?= kind-$(KIND_CLUSTER)
K8S_VERSION         ?= 1.37.0
HELM_UNITTEST_IMAGE ?= helmunittest/helm-unittest:4.3.0-1.2.1
HADOLINT_IMAGE      ?= hadolint/hadolint:v2.15.1
METRICS_SERVER_CHART_REPO    ?= https://kubernetes-sigs.github.io/metrics-server/
METRICS_SERVER_CHART_VERSION ?= 3.14.0

IMAGE_REPO          := ghcr.io/hermeto/go-app
APP_DIR             := app
APP_CHART           := charts/go-app
ROOT_CHART          := gitops/root
# Single sources of truth: the chart appVersion, the image tags pinned per environment, the Argo CD chart pin.
APP_VERSION         := $(shell awk '/^appVersion:/{gsub(/"/,"",$$2); print $$2}' $(APP_CHART)/Chart.yaml)
ENVIRONMENTS        := $(notdir $(wildcard environments/*))
ENV_IMAGE_TAGS      := $(sort $(shell awk 'FNR==1{f=0} /^image:/{f=1} f && /^  tag:/{gsub(/"/,"",$$2); print $$2; nextfile}' environments/*/values.yaml))
ARGOCD_CHART_REPO   := $(shell awk '/^argocd:/{f=1} f && /repoURL:/{print $$2; exit}' $(ROOT_CHART)/values.yaml)
ARGOCD_CHART_NAME   := $(shell awk '/^argocd:/{f=1} f && /name:/{print $$2; exit}' $(ROOT_CHART)/values.yaml)
ARGOCD_CHART_VERSION := $(shell awk '/^argocd:/{f=1} f && /version:/{print $$2; exit}' $(ROOT_CHART)/values.yaml)

BUILD_DIR           := build
ARGOCD_CHART_DIR    := $(BUILD_DIR)/charts/$(ARGOCD_CHART_NAME)-$(ARGOCD_CHART_VERSION)

# Kubernetes schemas, plus the community catalog for CRDs (Argo CD Application/AppProject). CustomResourceDefinition
# objects themselves have no published JSON schema and are skipped.
KUBECONFORM := kubeconform -strict -summary -kubernetes-version $(K8S_VERSION) -skip CustomResourceDefinition \
	-schema-location default \
	-schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0, 5)} /^[a-zA-Z0-9_-]+:.*##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

##@ Static checks (no cluster)

.PHONY: tools
tools: ## Check that the required tools are installed
	@for t in go golangci-lint docker helm kubectl kubeconform kind shellcheck trivy jq git; do \
	  if command -v $$t >/dev/null; then printf '  \033[32mok\033[0m      %s\n' "$$t"; else printf '  \033[31mmissing\033[0m %s\n' "$$t"; missing=1; fi; \
	done; exit $${missing:-0}

.PHONY: go-fmt
go-fmt: ## Fail if Go code is not gofmt-formatted
	@out=$$(cd $(APP_DIR) && gofmt -l .); [ -z "$$out" ] || { echo "not gofmt-formatted:"; echo "$$out"; exit 1; }

.PHONY: go-lint
go-lint: ## Run go vet and golangci-lint
	cd $(APP_DIR) && go vet ./...
	cd $(APP_DIR) && golangci-lint run ./...

.PHONY: go-test
go-test: ## Run the Go unit tests (race detector, coverage)
	cd $(APP_DIR) && go test -race -count=1 -cover ./...

.PHONY: docker-lint
docker-lint: ## Lint the Dockerfile with hadolint
	docker run --rm -i $(HADOLINT_IMAGE) < $(APP_DIR)/Dockerfile

.PHONY: helm-lint
helm-lint: ## helm lint both charts, the app chart once per environment
	helm lint --strict $(ROOT_CHART)
	@for env in $(ENVIRONMENTS); do echo "==> helm lint $(APP_CHART) ($$env)"; helm lint --strict $(APP_CHART) -f environments/$$env/values.yaml; done

.PHONY: helm-unittest
helm-unittest: ## Run the helm-unittest suites of both charts
	docker run --rm --user "$$(id -u):$$(id -g)" -v "$(CURDIR):/apps" -w /apps $(HELM_UNITTEST_IMAGE) $(APP_CHART) $(ROOT_CHART)

$(ARGOCD_CHART_DIR):
	mkdir -p $(BUILD_DIR)/charts
	helm pull $(ARGOCD_CHART_NAME) --repo $(ARGOCD_CHART_REPO) --version $(ARGOCD_CHART_VERSION) --untar --untardir $@-tmp
	mv $@-tmp/$(ARGOCD_CHART_NAME) $@ && rm -rf $@-tmp

.PHONY: helm-render
helm-render: $(ARGOCD_CHART_DIR) ## Render what Argo CD deploys (every environment, root, Argo CD) and validate it with kubeconform
	mkdir -p $(BUILD_DIR)/manifests
	@for env in $(ENVIRONMENTS); do \
	  helm template go-app $(APP_CHART) --namespace go-app-$$env --kube-version $(K8S_VERSION) \
	    -f environments/$$env/values.yaml > $(BUILD_DIR)/manifests/go-app-$$env.yaml; \
	done
	helm template root $(ROOT_CHART) --namespace argocd --kube-version $(K8S_VERSION) > $(BUILD_DIR)/manifests/root.yaml
	helm template argocd $(ARGOCD_CHART_DIR) --namespace argocd --kube-version $(K8S_VERSION) \
	  -f gitops/argocd/values.yaml > $(BUILD_DIR)/manifests/argocd.yaml
	$(KUBECONFORM) $(BUILD_DIR)/manifests e2e

.PHONY: test-scripts
test-scripts: ## Lint shell scripts with shellcheck
	shellcheck scripts/*.sh

.PHONY: security
security: ## Scan the Dockerfile, charts and manifests for misconfigurations (trivy)
	trivy config --disable-telemetry --severity MEDIUM,HIGH,CRITICAL --ignorefile .trivyignore.yaml --skip-dirs $(BUILD_DIR) --exit-code 1 .

.PHONY: check
check: go-fmt go-lint go-test docker-lint helm-lint helm-unittest helm-render test-scripts security ## Run every static check (what CI runs)

##@ Container image

.PHONY: image
# One image per version: the chart appVersion and every tag pinned in environments/ (during a promotion, dev and
# prod pin different tags). They are built from the code under test, each stamped with its own version.
image: ## Build the go-app image for the chart appVersion and every tag pinned in environments/
	@for t in $(sort $(APP_VERSION) $(ENV_IMAGE_TAGS)); do \
	  echo "==> $(IMAGE_REPO):$$t"; docker build --quiet --build-arg VERSION=$$t -t $(IMAGE_REPO):$$t $(APP_DIR); \
	done

.PHONY: image-scan
image-scan: image ## Scan the image for vulnerabilities (trivy)
	trivy image --disable-telemetry --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(IMAGE_REPO):$(APP_VERSION)

##@ Local environment (kind)

.PHONY: local-up
local-up: ## Create the kind cluster, with metrics-server
	@if kind get clusters 2>/dev/null | grep -qx '$(KIND_CLUSTER)'; then echo "kind cluster $(KIND_CLUSTER) already exists"; \
	else kind create cluster --name $(KIND_CLUSTER) --config $(KIND_CONFIG) --wait 120s; fi
	$(MAKE) metrics-server

# Managed clusters ship metrics-server; kind does not. Without it the HPA cannot read CPU usage and Argo CD reports
# the prod Application as Degraded. kubelets on kind serve self-signed certificates, hence --kubelet-insecure-tls.
.PHONY: metrics-server
metrics-server: ## Install metrics-server on the kind cluster (the HPA needs it)
	helm --kube-context $(KUBE_CONTEXT) upgrade --install metrics-server metrics-server \
	  --repo $(METRICS_SERVER_CHART_REPO) --version $(METRICS_SERVER_CHART_VERSION) \
	  --namespace kube-system --set 'args={--kubelet-insecure-tls}' --wait --timeout 5m

.PHONY: image-load
image-load: image ## Build the image and load it into the kind cluster
	kind load docker-image --name $(KIND_CLUSTER) $(foreach t,$(sort $(APP_VERSION) $(ENV_IMAGE_TAGS)),$(IMAGE_REPO):$(t))

.PHONY: bootstrap
bootstrap: $(ARGOCD_CHART_DIR) ## Install Argo CD and hand over to Git (REPO_URL/REPO_REVISION override the tracked repository)
	KUBE_CONTEXT=$(KUBE_CONTEXT) scripts/bootstrap.sh $(ARGOCD_CHART_DIR)

.PHONY: smoke
smoke: ## Run the smoke tests against the cluster
	KUBE_CONTEXT=$(KUBE_CONTEXT) scripts/smoke-test.sh

.PHONY: e2e
e2e: $(ARGOCD_CHART_DIR) local-up image-load ## Create kind, push the working tree to an in-cluster Git server, bootstrap Argo CD, run the e2e tests
	KUBE_CONTEXT=$(KUBE_CONTEXT) scripts/e2e.sh $(ARGOCD_CHART_DIR)

.PHONY: argocd-ui
argocd-ui: ## Print the initial admin password and port-forward the Argo CD UI on https://localhost:8080
	@echo "user:     admin"
	@echo "password: $$(kubectl --context $(KUBE_CONTEXT) -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
	kubectl --context $(KUBE_CONTEXT) -n argocd port-forward svc/argocd-server 8080:443

.PHONY: local-down
local-down: ## Delete the kind cluster
	kind delete cluster --name $(KIND_CLUSTER)

##@ Housekeeping

.PHONY: clean
clean: ## Remove build output
	rm -rf $(BUILD_DIR)
