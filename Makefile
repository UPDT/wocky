# vim: set noexpandtab ts=2 sw=2:
.PHONY: help unittest migrationtest release build push deploy shipit restart pods status top exec console shell describe logs follow cp

VERSION       ?= $(shell elixir ./version.exs)
RELEASE_NAME  ?= wocky
IMAGE_NAME    ?= hippware/$(shell echo $(RELEASE_NAME) | tr "_" "-")
IMAGE_TAG     ?= $(shell git rev-parse HEAD)
WOCKY_ENV     ?= testing
KUBE_NS       := wocky-$(WOCKY_ENV)
WOCKY_DB_HOST ?= localhost
WOCKY_DB_USER ?= postgres
MIX_ENV       ?= dev

help:
	@echo "Repo:    $(IMAGE_NAME)"
	@echo "Tag:     $(IMAGE_TAG)"
	@echo "Version: $(VERSION)"
	@echo ""
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

########################################################################
### Run tests in CI

check: ## Run mix check
	mix check --except dialyzer

migrationtest: undumpdb
	mix ecto.migrate

########################################################################
### Local database helpers

db_dump.gz:
	aws s3 cp s3://wocky-db-dumps/staging/wocky_staging.dump.gz db_dump.gz

undumpdb: db_dump.gz
	echo "CREATE DATABASE wocky_${MIX_ENV}" | PGPASSWORD=${WOCKY_DB_PASSWORD} psql -U ${WOCKY_DB_USER} -h ${WOCKY_DB_HOST} -w
	gunzip -c db_dump.gz | PGPASSWORD=${WOCKY_DB_PASSWORD} psql -U ${WOCKY_DB_USER} -h ${WOCKY_DB_HOST} -w wocky_${MIX_ENV}

dropdb:
	mix ecto.drop

resetdb: dropdb undumpdb

########################################################################
### Build release images

dockerlint: ## Run dockerlint on the Dockerfiles
	@echo "Checking Dockerfile.build..."
	@docker run -it --rm -v "${PWD}/Dockerfile.build":/Dockerfile:ro redcoolbeans/dockerlint:latest
	@echo "Checking Dockerfile.release..."
	@docker run -it --rm -v "${PWD}/Dockerfile.release":/Dockerfile:ro redcoolbeans/dockerlint:latest

kubeval: ## Run kubeval on all Kubernetes manifests
	@echo "Checking Kubernetes manifests..."
	@docker run -it --rm -v "${PWD}/k8s":/k8s garethr/kubeval k8s/*/*.yml*

release: ## Build the release tarball
	MIX_ENV=prod mix distillery.release --warnings-as-errors --name $(RELEASE_NAME)
	cp _build/prod/rel/$(RELEASE_NAME)/releases/$(VERSION)/$(RELEASE_NAME).tar.gz /artifacts

build: ## Build the release Docker image
	rm -f ${PWD}/tmp/artifacts/$(RELEASE_NAME).tar.gz
	docker build . -t wocky-build:latest -f Dockerfile.build
	docker run -it --rm \
		-v ${PWD}/tmp/artifacts:/artifacts \
		-e "RELEASE_NAME=$(RELEASE_NAME)" \
		wocky-build:latest make release
	docker build . -f Dockerfile.release \
		--build-arg RELEASE_NAME=$(RELEASE_NAME) \
		-t $(IMAGE_NAME):$(IMAGE_TAG) \
		-t $(IMAGE_NAME):latest

push: ## Push the Docker image to ECR
	docker push $(IMAGE_NAME):$(IMAGE_TAG)
	docker push $(IMAGE_NAME):latest

########################################################################
### Cluster deployment

deploy: ## Deploy the image to the cluster
	@docker run -it --rm -v "${PWD}/k8s":/k8s garethr/kubeval k8s/$(WOCKY_ENV)/*.yml*
	@./wocky-deploy $(WOCKY_ENV)

shipit: build push deploy ## Build, push and deploy the image

########################################################################
### Cluster ops

restart: ## Do a rolling restart of the running pods
	@kubectl patch deployment wocky -n $(KUBE_NS) \
		-p'{"spec":{"template":{"spec":{"containers":[{"name":"wocky","env":[{"name":"RESTART_","value":"$(shell date -u)"}]}]}}}}'

pods: ## Return a list of running pods
	@kubectl get pods -n $(KUBE_NS) -l 'app=wocky' -o jsonpath='{.items[].metadata.name}'

status: ## Show the deployment status
	@kubectl get deployments,pods -n $(KUBE_NS) -l 'app=wocky'

top: ## Show resource usage for app pods
	@kubectl top pod -n $(KUBE_NS) -l 'app=wocky'

watch: ## Watch the pods for changes
	@kubectl get pods -n $(KUBE_NS) -l 'app=wocky' -w

define first-pod
$(shell kubectl get pods -n $(KUBE_NS) -l 'app=wocky' -o jsonpath='{.items[0].metadata.name}')
endef

define do-exec
kubectl exec -it -n $(KUBE_NS) $(POD) $(1)
endef

define print-pod
@echo "Pod: $(POD)"
@echo ""
endef

exec: POD ?= $(first-pod)
exec: ## Execute $CMD on a pod
	$(call do-exec,$(CMD))

console: POD ?= $(first-pod)
console: ## Start an Iex remote console on a pod
	@$(call print-pod)
	@$(call do-exec,bin/wocky remote_console)

shell: POD ?= $(first-pod)
shell: ## Start a shell on a pod
	@$(call print-pod)
	@$(call do-exec,/bin/sh)

describe: POD ?= $(first-pod)
describe: ## Describe the current release on a pod
	@$(call print-pod)
	@$(call do-exec,bin/wocky describe)

logs: POD ?= $(first-pod)
logs: ## Show the logs for a pod
	@$(call print-pod)
	@kubectl logs -n $(KUBE_NS) $(POD)

follow: POD ?= $(first-pod)
follow: ## Follow the logs for a pod
	@$(call print-pod)
	@kubectl logs -n $(KUBE_NS) -f $(POD)

cp: POD ?= $(first-pod)
cp: ## Copy a file from the container
	@$(call print-pod)
	kubectl cp $(KUBE_NS)/$(POD):$(src) $(dest)
