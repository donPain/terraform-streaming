package dev.learning.streaming;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.time.Duration;
import java.time.Instant;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.api.common.typeinfo.Types;
import org.apache.flink.connector.base.DeliveryGuarantee;
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.datastream.SingleOutputStreamOperator;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.ProcessFunction;
import org.apache.flink.util.Collector;
import org.apache.flink.util.OutputTag;

public final class TelemetryJob {
    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final OutputTag<String> DLQ = new OutputTag<>("invalid-telemetry", Types.STRING);

    private TelemetryJob() {}

    public static void main(String[] args) throws Exception {
        String brokers = env("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092");
        String rawTopic = env("KAFKA_RAW_TOPIC", "machine.telemetry.raw");

        StreamExecutionEnvironment environment = StreamExecutionEnvironment.getExecutionEnvironment();
        environment.enableCheckpointing(10_000);

        KafkaSource<String> source = KafkaSource.<String>builder()
                .setBootstrapServers(brokers)
                .setTopics(rawTopic)
                .setGroupId("flink-telemetry-enricher")
                .setStartingOffsets(OffsetsInitializer.earliest())
                .setValueOnlyDeserializer(new SimpleStringSchema())
                .build();

        SingleOutputStreamOperator<String> enriched = environment
                .fromSource(source, WatermarkStrategy.noWatermarks(), "Kafka raw source")
                .uid("raw-source")
                .process(new ValidateAndEnrich())
                .name("validate and enrich")
                .uid("validate-enrich");

        DataStream<String> timestamped = enriched
                .assignTimestampsAndWatermarks(
                        WatermarkStrategy.<String>forBoundedOutOfOrderness(Duration.ofSeconds(5))
                                .withTimestampAssigner((event, ignored) -> eventTimestamp(event)))
                .name("event-time watermarks");

        timestamped
                .sinkTo(kafkaSink(brokers, env("KAFKA_ENRICHED_TOPIC", "machine.telemetry.enriched")))
                .name("Kafka enriched sink")
                .uid("enriched-sink");

        enriched.getSideOutput(DLQ)
                .sinkTo(kafkaSink(brokers, env("KAFKA_DLQ_TOPIC", "machine.telemetry.dlq")))
                .name("Kafka DLQ sink")
                .uid("dlq-sink");

        environment.execute("machine-telemetry-enricher");
    }

    static String enrich(String raw, String processedAt) throws Exception {
        JsonNode parsed = MAPPER.readTree(raw);
        if (!(parsed instanceof ObjectNode event)) {
            throw new IllegalArgumentException("event must be a JSON object");
        }

        requireText(event, "machineId");
        Instant.parse(requireText(event, "timestamp"));
        requireRange(event, "latitude", -90, 90);
        requireRange(event, "longitude", -180, 180);
        requireRange(event, "speed", 0, Double.MAX_VALUE);
        double temperature = requireRange(event, "temperature", -100, 250);
        requireRange(event, "fuelLevel", 0, 100);

        event.put("processedAt", processedAt);
        event.put("status", temperature > 90 ? "OVERHEATING" : "NORMAL");
        return MAPPER.writeValueAsString(event);
    }

    private static KafkaSink<String> kafkaSink(String brokers, String topic) {
        return KafkaSink.<String>builder()
                .setBootstrapServers(brokers)
                .setDeliveryGuarantee(DeliveryGuarantee.AT_LEAST_ONCE)
                .setRecordSerializer(KafkaRecordSerializationSchema.builder()
                        .setTopic(topic)
                        .setValueSerializationSchema(new SimpleStringSchema())
                        .build())
                .build();
    }

    private static long eventTimestamp(String event) {
        try {
            return Instant.parse(MAPPER.readTree(event).path("timestamp").asText()).toEpochMilli();
        } catch (Exception ignored) {
            return System.currentTimeMillis();
        }
    }

    private static String requireText(ObjectNode event, String field) {
        String value = event.path(field).asText("");
        if (value.isBlank()) {
            throw new IllegalArgumentException(field + " is required");
        }
        return value;
    }

    private static double requireRange(ObjectNode event, String field, double minimum, double maximum) {
        JsonNode value = event.get(field);
        if (value == null || !value.isNumber() || value.asDouble() < minimum || value.asDouble() > maximum) {
            throw new IllegalArgumentException(field + " is outside the accepted range");
        }
        return value.asDouble();
    }

    private static String env(String name, String fallback) {
        return System.getenv().getOrDefault(name, fallback);
    }

    private static final class ValidateAndEnrich extends ProcessFunction<String, String> {
        private final long delayMs = Long.parseLong(env("PROCESSING_DELAY_MS", "0"));

        @Override
        public void processElement(String raw, Context context, Collector<String> output) throws Exception {
            if (delayMs > 0) {
                Thread.sleep(delayMs); // ponytail: intentional learning throttle; replace with real slow I/O in production tests.
            }
            try {
                output.collect(enrich(raw, Instant.now().toString()));
            } catch (Exception error) {
                ObjectNode dlq = MAPPER.createObjectNode();
                dlq.put("failedAt", Instant.now().toString());
                dlq.put("error", error.getMessage());
                dlq.put("raw", raw);
                context.output(DLQ, MAPPER.writeValueAsString(dlq));
            }
        }
    }
}
