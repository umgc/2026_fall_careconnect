package com.careconnect.util;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Utility class for converting the {@code daysOfWeek} field
 * between JSON and Java objects.
 *
 * <p>
 * In the database, {@code daysOfWeek} is stored as a JSON string
 * representing a list of booleans (one for each day of the week).
 * This class provides helper methods to:
 * <ul>
 * <li>Parse the JSON string into a {@link List}&lt;{@link Boolean}&gt;</li>
 * <li>Serialize a {@link List}&lt;{@link Boolean}&gt; back into a JSON
 * string</li>
 * </ul>
 * </p>
 *
 * <p>
 * Example JSON representation of {@code daysOfWeek}:
 * </p>
 *
 * <pre>
 * "[true, false, true, false, false, true, false]"
 * </pre>
 * <p>
 * → Monday, Wednesday, Saturday
 *
 * <p>
 * This utility is typically used in the {@code TaskServiceV2} layer
 * when mapping between entities and DTOs.
 * </p>
 */
public class TaskMapper {
    /**
     * Shared Jackson object mapper for JSON serialization/deserialization.
     */
    private static final ObjectMapper mapper = new ObjectMapper();

    /**
     * Parses a JSON string into a list of booleans representing days of the week.
     *
     * <p>
     * Each element corresponds to a day (starting with Sunday or Monday,
     * depending on business rules). A value of {@code true} means the task
     * applies on that day.
     * </p>
     *
     * <p>
     * Example input:
     * </p>
     *
     * <pre>
     * "[true, false, true, false, false, true, false]"
     * </pre>
     *
     * @param json JSON string representation of a list of booleans
     * @return list of booleans, or {@code null} if input is {@code null}
     * @throws RuntimeException if parsing fails
     */
    public static List<Boolean> parseDays(String json) {
        if (json == null) {
            return null;
        }

        String raw = json.trim();
        if (raw.isEmpty() || "null".equalsIgnoreCase(raw)) {
            return null;
        }

        try {
            List<Boolean> parsed = mapper.readValue(raw, new TypeReference<List<Boolean>>() {
            });
            return normalizeToSeven(parsed);
        } catch (Exception ignored) {
            // Fall through to backward-compatible formats.
        }

        // Support double-encoded JSON strings, e.g.
        // "\"[true,false,true,false,false,true,false]\"".
        try {
            String inner = mapper.readValue(raw, String.class);
            if (inner != null && !inner.trim().equals(raw)) {
                return parseDays(inner);
            }
        } catch (Exception ignored) {
        }

        // Support JSON array of names, e.g. ["MONDAY", "WEDNESDAY"].
        try {
            List<String> names = mapper.readValue(raw, new TypeReference<List<String>>() {
            });
            List<Boolean> fromNames = parseDayNames(names);
            if (fromNames != null) {
                return fromNames;
            }
        } catch (Exception ignored) {
        }

        // Support JSON object map, e.g. {"monday":true,"wednesday":true}.
        try {
            Map<String, Object> map = mapper.readValue(raw, new TypeReference<LinkedHashMap<String, Object>>() {
            });
            List<Boolean> fromMap = parseDayMap(map);
            if (fromMap != null) {
                return fromMap;
            }
        } catch (Exception ignored) {
        }

        // Support legacy CSV names, e.g. "MON,WED,FRI" / "monday, wednesday".
        List<Boolean> fromCsv = parseCsvDayNames(raw);
        if (fromCsv != null) {
            return fromCsv;
        }

        // Fail-safe for read paths: return null so GET endpoints do not fail on
        // legacy or malformed persisted values.
        return null;
    }

    /**
     * Serializes a list of booleans into a JSON string representation.
     *
     * <p>
     * Each boolean represents whether the task occurs on a given day.
     * </p>
     *
     * <p>
     * Example input:
     * </p>
     *
     * <pre>
     *   [true, false, true, false, false, true, false]
     * </pre>
     * <p>
     * → Output:
     *
     * <pre>
     * "[true,false,true,false,false,true,false]"
     * </pre>
     *
     * @param days list of booleans, one per day of the week
     * @return JSON string representation, or {@code null} if input is {@code null}
     * @throws RuntimeException if serialization fails
     */
    public static String serializeDays(List<Boolean> days) {
        if (days == null)
            return null;
        try {
            return mapper.writeValueAsString(normalizeToSeven(days));
        } catch (Exception e) {
            throw new RuntimeException("Failed to serialize daysOfWeek JSON", e);
        }
    }

    private static List<Boolean> normalizeToSeven(List<Boolean> input) {
        List<Boolean> normalized = new ArrayList<>(Collections.nCopies(7, Boolean.FALSE));
        if (input == null) {
            return normalized;
        }
        int max = Math.min(7, input.size());
        for (int i = 0; i < max; i++) {
            normalized.set(i, Boolean.TRUE.equals(input.get(i)));
        }
        return normalized;
    }

    private static List<Boolean> parseDayNames(List<String> dayNames) {
        if (dayNames == null || dayNames.isEmpty()) {
            return null;
        }
        List<Boolean> result = new ArrayList<>(Collections.nCopies(7, Boolean.FALSE));
        boolean any = false;
        for (String name : dayNames) {
            int idx = dayNameToIndex(name);
            if (idx >= 0) {
                result.set(idx, true);
                any = true;
            }
        }
        return any ? result : null;
    }

    private static List<Boolean> parseDayMap(Map<String, Object> dayMap) {
        if (dayMap == null || dayMap.isEmpty()) {
            return null;
        }
        List<Boolean> result = new ArrayList<>(Collections.nCopies(7, Boolean.FALSE));
        boolean any = false;
        for (Map.Entry<String, Object> entry : dayMap.entrySet()) {
            int idx = dayNameToIndex(entry.getKey());
            if (idx < 0) {
                continue;
            }
            boolean selected = false;
            Object value = entry.getValue();
            if (value instanceof Boolean b) {
                selected = b;
            } else if (value instanceof Number n) {
                selected = n.intValue() != 0;
            } else if (value instanceof String s) {
                String normalized = s.trim().toLowerCase(Locale.ROOT);
                selected = "true".equals(normalized) || "1".equals(normalized) || "yes".equals(normalized);
            }
            if (selected) {
                result.set(idx, true);
                any = true;
            }
        }
        return any ? result : null;
    }

    private static List<Boolean> parseCsvDayNames(String csv) {
        if (csv == null || csv.isBlank()) {
            return null;
        }
        String[] parts = csv.split(",");
        if (parts.length == 0) {
            return null;
        }
        List<String> names = new ArrayList<>();
        for (String part : parts) {
            names.add(part == null ? null : part.trim());
        }
        return parseDayNames(names);
    }

    /**
     * Converts day token to index in boolean list (Sun=0..Sat=6).
     */
    private static int dayNameToIndex(String raw) {
        if (raw == null) {
            return -1;
        }
        String s = raw.trim().toLowerCase(Locale.ROOT);
        if (s.isEmpty()) {
            return -1;
        }

        if (s.startsWith("sun")) {
            return 0;
        }
        if (s.startsWith("mon")) {
            return 1;
        }
        if (s.startsWith("tue")) {
            return 2;
        }
        if (s.startsWith("wed")) {
            return 3;
        }
        if (s.startsWith("thu")) {
            return 4;
        }
        if (s.startsWith("fri")) {
            return 5;
        }
        if (s.startsWith("sat")) {
            return 6;
        }
        return -1;
    }
}
