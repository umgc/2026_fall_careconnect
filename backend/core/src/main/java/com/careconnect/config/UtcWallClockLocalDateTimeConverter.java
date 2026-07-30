package com.careconnect.config;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;
import java.sql.Timestamp;
import java.time.LocalDateTime;

/**
 * Persists {@link LocalDateTime} UTC wall-clock values without applying the JVM /
 * {@code hibernate.jdbc.time_zone} shift that otherwise moves timestamps by the local offset
 * (e.g. +4h EDT) and breaks sentiment-clip seeks against the composited MP4.
 */
@Converter(autoApply = false)
public class UtcWallClockLocalDateTimeConverter
        implements AttributeConverter<LocalDateTime, Timestamp> {

    @Override
    public Timestamp convertToDatabaseColumn(final LocalDateTime attribute) {
        return attribute == null ? null : Timestamp.valueOf(attribute);
    }

    @Override
    public LocalDateTime convertToEntityAttribute(final Timestamp dbData) {
        return dbData == null ? null : dbData.toLocalDateTime();
    }
}
