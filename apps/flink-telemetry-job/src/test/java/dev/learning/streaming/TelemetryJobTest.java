package dev.learning.streaming;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

class TelemetryJobTest {
    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Test
    void enrichesValidEventsAndRejectsMissingFields() throws Exception {
        String raw = """
                {"machineId":"tractor-001","timestamp":"2026-01-01T00:00:00Z","latitude":-21.2,
                 "longitude":-50.43,"speed":12.5,"temperature":93.2,"fuelLevel":64.5}
                """;
        JsonNode enriched = MAPPER.readTree(TelemetryJob.enrich(raw, "2026-01-01T00:00:01Z"));

        assertEquals("OVERHEATING", enriched.path("status").asText());
        assertEquals("2026-01-01T00:00:01Z", enriched.path("processedAt").asText());
        assertThrows(IllegalArgumentException.class, () -> TelemetryJob.enrich("{}", "2026-01-01T00:00:01Z"));
    }
}
