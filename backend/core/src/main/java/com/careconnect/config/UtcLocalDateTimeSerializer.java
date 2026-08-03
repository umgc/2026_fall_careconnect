package com.careconnect.config;

import com.fasterxml.jackson.core.JsonGenerator;
import com.fasterxml.jackson.databind.JsonSerializer;
import com.fasterxml.jackson.databind.SerializerProvider;
import java.io.IOException;
import java.time.LocalDateTime;
import java.time.ZoneOffset;

/**
 * Emits UTC wall-clock {@link LocalDateTime} values as Instant {@code ...Z} strings so Flutter
 * {@code DateTime.parse} does not treat naive ISO datetimes as browser-local time (which shifts
 * sentiment-clip windows by the local UTC offset).
 */
public class UtcLocalDateTimeSerializer extends JsonSerializer<LocalDateTime> {

    @Override
    public void serialize(
            final LocalDateTime value,
            final JsonGenerator gen,
            final SerializerProvider serializers)
            throws IOException {
        if (value == null) {
            gen.writeNull();
            return;
        }
        gen.writeString(value.atZone(ZoneOffset.UTC).toInstant().toString());
    }
}
