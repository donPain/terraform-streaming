# Kafka and Strimzi guide

## Core concepts

- **Broker:** Kafka server that stores partition logs and serves producers/consumers. This lab has one.
- **Controller:** KRaft role that manages cluster metadata and elections. The same Pod is both broker and controller locally.
- **Topic:** Named append-only stream. The three topics separate input, output, and rejected events.
- **Partition:** Ordered topic shard. Raw/enriched have three to experiment with parallelism.
- **Replica:** Copy of a partition on a broker. Replication factor is one because there is one broker.
- **Leader:** Replica handling reads/writes for a partition. With one replica, it is always on the only broker.
- **Consumer group:** Consumers sharing a group divide partitions. A partition is assigned to at most one group member at a time.
- **Offset:** Position of a record within one partition. Groups commit offsets to remember progress.
- **Retention:** Time/size policy controlling when old log segments can be deleted; it is not message acknowledgement.

## What Strimzi creates

```text
KafkaNodePool + Kafka CR
  └─ Strimzi Cluster Operator
      ├─ StrimziPodSet → Kafka broker/controller Pod
      ├─ bootstrap/headless Services
      ├─ broker ConfigMaps and Secrets
      ├─ PVC
      └─ Entity Operator
          ├─ Topic Operator ← KafkaTopic CRs
          └─ User Operator
```

Inspect the API and custom-resource schemas:

```bash
kubectl get crd kafkas.kafka.strimzi.io -o yaml
kubectl explain kafka.spec.kafka.listeners
kubectl explain kafkanodepool.spec.roles
kubectl explain kafkatopic.spec.partitions
kubectl api-resources --api-group=kafka.strimzi.io
```

Inspect status and generated objects:

```bash
kubectl get kafka -n streaming
kubectl get kafkanodepool -n streaming
kubectl get kafkatopics -n streaming
kubectl get pods -n streaming -l strimzi.io/cluster=local-kafka
kubectl get strimzipodset,svc,pvc -n streaming
kubectl describe kafka local-kafka -n streaming
kubectl logs deployment/strimzi-cluster-operator -n streaming --tail=100
```

## Kafka CLI inside Kubernetes

The Kafka image already contains the CLI tools:

```bash
KAFKA_POD=local-kafka-dual-role-0

kubectl exec -n streaming "$KAFKA_POD" -c kafka -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 --list

kubectl exec -n streaming "$KAFKA_POD" -c kafka -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 \
  --describe --topic machine.telemetry.raw

kubectl exec -n streaming "$KAFKA_POD" -c kafka -- \
  bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --group flink-telemetry-enricher

kubectl exec -n streaming "$KAFKA_POD" -c kafka -- \
  bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --group telemetry-learning-consumer
```

Consume a few records and stop with `ctrl-c`:

```bash
make consume-raw
make consume-enriched
make consume-dlq
```

Produce a manual invalid event:

```bash
printf '{"temperature":"bad"}\n' | kubectl exec -i -n streaming "$KAFKA_POD" -c kafka -- \
  bin/kafka-console-producer.sh --bootstrap-server localhost:9092 \
  --topic machine.telemetry.raw
```

## Local limits and production

The one-broker configuration cannot stay available while its broker restarts and cannot demonstrate replica election. It intentionally uses replication factor one, `min.insync.replicas=1`, and disposable PVC deletion.

Production MSK or Strimzi would use multiple brokers across zones, replication factor three, `min.insync.replicas=2`, TLS/SASL, quotas, capacity planning, rack awareness, longer retention, backups where required, and alerts for under-replicated/offline partitions and consumer lag.
