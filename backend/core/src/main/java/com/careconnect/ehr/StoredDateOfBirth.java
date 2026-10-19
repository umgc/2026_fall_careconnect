package com.careconnect.ehr;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.time.format.ResolverStyle;
import java.util.Optional;

/**
 * Reads {@code patient.dob}, which is a varchar the application writes in two shapes: the
 * onboarding registration screen stores {@code MM/DD/YYYY}, the sign-up screen stores ISO-8601.
 * <p>
 * One place for that knowledge, because two things now depend on it and must not disagree:
 * identity reconciliation compares the stored value against a FHIR {@code birthDate}, and the
 * raw-payload retention purge decides from it whether a patient is past the age a minor's
 * records must be kept to. A third format added to one and not the other would make them
 * disagree about the same patient.
 */
public final class StoredDateOfBirth {

    /** STRICT so 02/30/1950 is rejected, not silently rolled to March. */
    private static final DateTimeFormatter US_DATE =
            DateTimeFormatter.ofPattern("MM/dd/uuuu").withResolverStyle(ResolverStyle.STRICT);

    private StoredDateOfBirth() {
    }

    /**
     * @return the date, or empty when the value is null, blank or in neither shape. Empty means
     *         <em>unknown</em>; callers must not read it as any particular age.
     */
    public static Optional<LocalDate> parse(final String stored) {
        if (stored == null || stored.isBlank()) {
            return Optional.empty();
        }
        final String trimmed = stored.trim();
        try {
            return Optional.of(LocalDate.parse(trimmed));
        } catch (DateTimeParseException notIso) {
            try {
                return Optional.of(LocalDate.parse(trimmed, US_DATE));
            } catch (DateTimeParseException notUs) {
                return Optional.empty();
            }
        }
    }
}
