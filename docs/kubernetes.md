# Kubernetes and k9s cheat sheet

## Objects you will meet

| Object | Example in this lab | What it teaches |
|---|---|---|
| Pod | Kafka broker, producer, TaskManager | Smallest scheduled unit; containers in a Pod share network and volumes. |
| Deployment | producer, consumer, MinIO, operators | Maintains stateless replica count and performs rolling updates. |
| StatefulSet / StrimziPodSet | Prometheus / Kafka | Stable identity and storage-aware workload management. Strimzi now uses its own PodSet CR for Kafka. |
| Service | Kafka bootstrap, MinIO API, Grafana | Stable virtual IP/DNS in front of changing Pods. |
| ConfigMap | Kafka metric rules, Grafana dashboard | Non-secret configuration delivered through the API. |
| Secret | MinIO credentials | Base64-encoded Kubernetes secret data; not encryption by itself. |
| Namespace | streaming, processing, storage, observability | Name and RBAC scope. |
| ServiceAccount | operators, Flink, telemetry apps | Pod identity for calls to the Kubernetes API. |
| Role/RoleBinding | operator chart resources | Permissions and assignment within a namespace. |
| PersistentVolumeClaim | Kafka and MinIO data | A workload's request for durable storage. |
| PersistentVolume | kind host-path volume | The storage satisfying a claim. |
| CRD | Kafka, KafkaTopic, FlinkDeployment | Extends the Kubernetes API with a new kind/schema. |
| Operator | Strimzi, Flink, Prometheus | A controller that reconciles domain-specific custom resources. |
| requests/limits | every workload | Scheduler reservation and container resource ceiling. |
| probes | producer and MinIO | Readiness controls traffic; liveness requests restart on a failed process. |
| labels/selectors | `app=telemetry-producer` | Loose coupling between Deployments, Pods, Services, and monitors. |

## Everyday kubectl

```bash
# Context and discovery
kubectl config current-context
kubectl cluster-info
kubectl api-resources
kubectl api-versions
kubectl explain deployment
kubectl explain deployment.spec.template.spec.containers.resources

# Inventory
kubectl get nodes -o wide
kubectl get namespaces
kubectl get pods -A -o wide
kubectl get deploy,statefulset,service -A
kubectl get configmap,secret -A
kubectl get pv
kubectl get pvc -A
kubectl get events -A --sort-by=.lastTimestamp

# Investigate one workload
kubectl describe pod POD -n NAMESPACE
kubectl logs POD -n NAMESPACE
kubectl logs POD -n NAMESPACE --previous
kubectl logs deployment/telemetry-producer -n streaming -f
kubectl get pod POD -n NAMESPACE -o yaml

# Observe changes
kubectl get pods -A -w
kubectl rollout status deployment/telemetry-producer -n streaming
kubectl top pods -A     # available after metrics-server; Prometheus/Grafana is used here instead

# Networking and DNS
kubectl get service,endpoints,endpointslice -A
kubectl run dns-test --rm -it --restart=Never --image=busybox:1.37 -- \
  nslookup local-kafka-kafka-bootstrap.streaming.svc.cluster.local

# RBAC
kubectl get serviceaccount,role,rolebinding -A
kubectl auth can-i --as system:serviceaccount:streaming:telemetry-apps list pods -n streaming
kubectl auth can-i --as system:serviceaccount:processing:flink create pods -n processing
```

The first RBAC command should return `no`: the telemetry applications do not need Kubernetes API access. The Flink ServiceAccount should be allowed to create its runtime resources.

## Inspect operator-created resources

```bash
kubectl get crd | grep -E 'strimzi|flink|monitoring.coreos.com'
kubectl get kafka,kafkanodepool,kafkatopic -n streaming
kubectl get strimzipodset,service,pvc,secret -n streaming
kubectl get flinkdeployment -n processing -o yaml
kubectl get podmonitor,servicemonitor -A
kubectl get prometheus -n observability
```

Owner references show who created an object:

```bash
kubectl get pod local-kafka-dual-role-0 -n streaming \
  -o jsonpath='{.metadata.ownerReferences}'
```

## k9s navigation

Start in all namespaces:

```bash
k9s -A
```

Useful keys:

| Key | Action |
|---|---|
| `:` | Open command mode; type `pods`, `deploy`, `svc`, `pvc`, `kafka`, `flinkdeployment`, or `crd`. |
| `0` | Show all namespaces. |
| `1`–`9` | Switch to a favorite namespace if configured. |
| `/` | Filter the current list; try `/telemetry` or `/local-kafka`. |
| `Enter` | Drill into the selected object. |
| `d` | Describe. |
| `l` | Logs; `p` toggles previous container logs. |
| `s` | Open a shell in the selected container. |
| `y` | View YAML. |
| `e` | Edit live YAML—use only for the drift lab. |
| `ctrl-d` | Delete selected object; confirmation is required. |
| `?` | Context-sensitive help. |
| `esc` | Go back. |
| `ctrl-c` | Exit. |

In k9s, watch a Kafka Pod return after deletion, then move to `:events` to correlate scheduling, image, volume, and probe events.

## Networking model

Every Pod gets an IP. Services select Pods by labels and provide stable DNS. `ClusterIP` Services are reachable only inside the cluster. `kubectl port-forward` creates a temporary local tunnel for learning UIs without an ingress controller or NodePort.

No NetworkPolicy is installed in the first version. Namespace separation alone does not block traffic. Production should default-deny ingress/egress, then explicitly allow DNS, Kafka, MinIO, monitoring, and API-server flows.
