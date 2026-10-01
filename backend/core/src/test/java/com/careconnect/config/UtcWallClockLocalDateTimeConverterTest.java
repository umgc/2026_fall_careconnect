package com.careconnect.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.module.SimpleModule;

import java.sql.Timestamp;
import java.time.LocalDateTime;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

@DisplayName("UTC wall-clock LocalDateTime helpers")
class UtcWallClockLocalDateTimeConverterTest {

    @Test
    @DisplayName("converter round-trips LocalDateTime without JVM zone shift")
    void converter_roundTripsWithoutZoneShift() {
        final UtcWallClockLocalDateTimeConverter converter =
                new UtcWallClockLocalDateTimeConverter();
        final LocalDateTime wall = LocalDateTime.of(2026, 7, 25, 0, 29, 50, 103811000);

        final Timestamp db = converter.convertToDatabaseColumn(wall);
        final LocalDateTime back = converter.convertToEntityAttribute(db);

        assertThat(db.toLocalDateTime()).isEqualTo(wall);
        assertThat(back).isEqualTo(wall);
    }

    @Test
    @DisplayName("serializer emits Instant Z so Flutter does not treat value as local")
    void serializer_emitsInstantZ() throws Exception {
        final ObjectMapper mapper = new ObjectMapper();
        final SimpleModule module = new SimpleModule();
        module.addSerializer(LocalDateTime.class, new UtcLocalDateTimeSerializer());
        mapper.registerModule(module);

        final String json =
                mapper.writeValueAsString(LocalDateTime.of(2026, 7, 25, 4, 29, 50, 103811000));

        assertThat(json).isEqualTo("\"2026-07-25T04:29:50.103811Z\"");
    }
}
