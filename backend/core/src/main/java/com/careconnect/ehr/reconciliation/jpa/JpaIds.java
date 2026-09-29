package com.careconnect.ehr.reconciliation.jpa;

import java.util.Objects;

/**
 * Coerces the reconciliation library's {@code Object} ids to this codebase's {@code Long} keys.
 * <p>
 * The library types patient and source ids as {@code Object} so an adapter is not forced onto any
 * particular key type. These JPA implementations are where that generality ends, and this is the
 * single place the narrowing happens — loudly, with the parameter named, rather than as a
 * {@code ClassCastException} from somewhere further in.
 */
final class JpaIds {

    private JpaIds() {
    }

    static Long asLong(Object id, String name) {
        Objects.requireNonNull(id, name);
        if (id instanceof Long value) {
            return value;
        }
        if (id instanceof Number value) {
            return value.longValue();
        }
        if (id instanceof CharSequence value) {
            try {
                return Long.valueOf(value.toString().trim());
            } catch (NumberFormatException e) {
                throw new IllegalArgumentException(
                        name + " must be a numeric id for the JPA store, got: " + value, e);
            }
        }
        throw new IllegalArgumentException(
                name + " must be a numeric id for the JPA store, got " + id.getClass().getName());
    }
}
