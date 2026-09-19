SHELL := /bin/bash
CLUSTER_NAME ?= streaming-lab
TF := terraform -chdir=terraform

.PHONY: help check-tools cluster-create cluster-delete cluster-status \
	terraform-init terraform-fmt terraform-validate terraform-operators-plan \
	terraform-operators strimzi-plan strimzi-install flink-operator-plan flink-operator-install \
	terraform-plan terraform-apply terraform-destroy \
	apps-test images-build images-load images apps-clean kafka-status kafka-describe \
	flink-status producer-logs consumer-logs flink-logs consume-raw consume-enriched \
	consume-dlq grafana prometheus minio health clean

help:
	@echo "Run targets one at a time; see README.md Learning Mode for explanations."
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-28s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

check-tools: ## Show required local tool versions.
	@echo '+ docker version; kind version; kubectl version --client; terraform version; helm version'
	@docker version --format 'Docker server {{.Server.Version}}'
	@kind version
	@kubectl version --client
	@terraform version
	@helm version

cluster-create: ## Create the three-node kind cluster.
	@echo '+ kind create cluster --config kind/cluster.yaml'
	kind create cluster --config kind/cluster.yaml

cluster-delete: ## Delete only the kind cluster (Terraform state remains local).
	@echo '+ kind delete cluster --name $(CLUSTER_NAME)'
	kind delete cluster --name $(CLUSTER_NAME)

cluster-status: ## Inspect nodes, namespaces, storage classes, and all pods.
	@echo '+ kubectl get nodes -o wide'
	kubectl get nodes -o wide
	@echo '+ kubectl get namespaces'
	kubectl get namespaces
	@echo '+ kubectl get storageclass,pv,pvc -A'
	kubectl get storageclass,pv,pvc -A
	@echo '+ kubectl get pods -A'
	kubectl get pods -A

terraform-init: ## Download Terraform providers and initialize local state.
	@echo '+ $(TF) init'
	$(TF) init

terraform-fmt: ## Format all Terraform files.
	@echo '+ terraform fmt -recursive terraform'
	terraform fmt -recursive terraform

terraform-validate: ## Validate Terraform syntax and provider schemas.
	@echo '+ $(TF) validate'
	$(TF) validate

terraform-operators-plan: ## Plan only operator Helm releases so their CRDs can be installed first.
	@echo '+ $(TF) plan -target=helm_release.strimzi_operator -target=helm_release.flink_operator'
	$(TF) plan -target=helm_release.strimzi_operator -target=helm_release.flink_operator

terraform-operators: ## Install Strimzi and Flink operators and their CRDs.
	@echo '+ $(TF) apply -target=helm_release.strimzi_operator -target=helm_release.flink_operator'
	$(TF) apply -target=helm_release.strimzi_operator -target=helm_release.flink_operator

strimzi-plan: ## Plan only the Strimzi operator and its namespace dependency.
	@echo '+ $(TF) plan -target=helm_release.strimzi_operator'
	$(TF) plan -target=helm_release.strimzi_operator

strimzi-install: ## Install only Strimzi for the incremental Kafka lesson.
	@echo '+ $(TF) apply -target=helm_release.strimzi_operator'
	$(TF) apply -target=helm_release.strimzi_operator

flink-operator-plan: ## Plan only the Flink Kubernetes Operator.
	@echo '+ $(TF) plan -target=helm_release.flink_operator'
	$(TF) plan -target=helm_release.flink_operator

flink-operator-install: ## Install only the Flink Kubernetes Operator.
	@echo '+ $(TF) apply -target=helm_release.flink_operator'
	$(TF) apply -target=helm_release.flink_operator

terraform-plan: ## Plan the complete platform after operator CRDs exist.
	@echo '+ $(TF) plan -out=tfplan'
	$(TF) plan -out=tfplan

terraform-apply: ## Apply the reviewed tfplan file.
	@echo '+ $(TF) apply tfplan'
	$(TF) apply tfplan

terraform-destroy: ## Destroy resources recorded in Terraform state.
	@echo '+ $(TF) destroy'
	$(TF) destroy

apps-test: ## Run the producer self-check and Flink Maven tests.
	@echo '+ cd apps/telemetry-producer && python3 -m unittest -v'
	cd apps/telemetry-producer && python3 -m unittest -v
	@echo '+ mvn -f apps/flink-telemetry-job/pom.xml test'
	mvn -f apps/flink-telemetry-job/pom.xml test

images-build: ## Build all three local application images.
	@echo '+ mvn -f apps/flink-telemetry-job/pom.xml clean package'
	mvn -f apps/flink-telemetry-job/pom.xml clean package
	@echo '+ docker build -t local/telemetry-producer:dev apps/telemetry-producer'
	docker build -t local/telemetry-producer:dev apps/telemetry-producer
	@echo '+ docker build -t local/telemetry-consumer:dev apps/telemetry-consumer'
	docker build -t local/telemetry-consumer:dev apps/telemetry-consumer
	@echo '+ docker build -t local/flink-telemetry-job:dev apps/flink-telemetry-job'
	docker build -t local/flink-telemetry-job:dev apps/flink-telemetry-job

images-load: ## Copy local images into every kind node.
	@echo '+ kind load docker-image --name $(CLUSTER_NAME) local/telemetry-producer:dev local/telemetry-consumer:dev local/flink-telemetry-job:dev'
	kind load docker-image --name $(CLUSTER_NAME) local/telemetry-producer:dev local/telemetry-consumer:dev local/flink-telemetry-job:dev

images: images-build images-load ## Build and load local images.

apps-clean: ## Remove Maven build output only.
	@echo '+ mvn -f apps/flink-telemetry-job/pom.xml clean'
	mvn -f apps/flink-telemetry-job/pom.xml clean

kafka-status: ## Show Kafka, node pool, topics, pods, and PVCs.
	@echo '+ kubectl get kafka,kafkanodepool,kafkatopic,pods,pvc -n streaming'
	kubectl get kafka,kafkanodepool,kafkatopic,pods,pvc -n streaming

kafka-describe: ## Show Strimzi reconciliation status and recent events.
	@echo '+ kubectl describe kafka local-kafka -n streaming'
	kubectl describe kafka local-kafka -n streaming

flink-status: ## Show the FlinkDeployment and operator-created pods.
	@echo '+ kubectl get flinkdeployment,pods -n processing -o wide'
	kubectl get flinkdeployment,pods -n processing -o wide

producer-logs: ## Follow producer logs.
	@echo '+ kubectl logs -n streaming deployment/telemetry-producer -f'
	kubectl logs -n streaming deployment/telemetry-producer -f

consumer-logs: ## Follow enriched-event consumer logs.
	@echo '+ kubectl logs -n streaming deployment/telemetry-consumer -f'
	kubectl logs -n streaming deployment/telemetry-consumer -f

flink-logs: ## Follow the Flink JobManager logs.
	@echo '+ kubectl logs -n processing -l component=jobmanager --all-containers=true -f --tail=100'
	kubectl logs -n processing -l component=jobmanager --all-containers=true -f --tail=100

consume-raw: ## Read raw events with Kafka's console consumer.
	@echo '+ kubectl exec -n streaming local-kafka-dual-role-0 -c kafka -- bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic machine.telemetry.raw --from-beginning'
	kubectl exec -n streaming local-kafka-dual-role-0 -c kafka -- bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic machine.telemetry.raw --from-beginning

consume-enriched: ## Read enriched events with Kafka's console consumer.
	@echo '+ kubectl exec -n streaming local-kafka-dual-role-0 -c kafka -- bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic machine.telemetry.enriched --from-beginning'
	kubectl exec -n streaming local-kafka-dual-role-0 -c kafka -- bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic machine.telemetry.enriched --from-beginning

consume-dlq: ## Read rejected events from the DLQ.
	@echo '+ kubectl exec -n streaming local-kafka-dual-role-0 -c kafka -- bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic machine.telemetry.dlq --from-beginning'
	kubectl exec -n streaming local-kafka-dual-role-0 -c kafka -- bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic machine.telemetry.dlq --from-beginning

grafana: ## Port-forward Grafana to http://localhost:3000.
	@echo '+ kubectl port-forward -n observability svc/monitoring-grafana 3000:80'
	kubectl port-forward -n observability svc/monitoring-grafana 3000:80

prometheus: ## Port-forward Prometheus to http://localhost:9090.
	@echo '+ kubectl port-forward -n observability svc/monitoring-kube-prometheus-prometheus 9090:9090'
	kubectl port-forward -n observability svc/monitoring-kube-prometheus-prometheus 9090:9090

minio: ## Port-forward MinIO Console to http://localhost:9001.
	@echo '+ kubectl port-forward -n storage svc/minio-console 9001:9001'
	kubectl port-forward -n storage svc/minio-console 9001:9001

health: ## Print a one-line health result for every platform component.
	@echo '+ ./scripts/health-check.sh'
	./scripts/health-check.sh

clean: terraform-destroy cluster-delete apps-clean ## Destroy the platform, cluster, and local Maven output.
