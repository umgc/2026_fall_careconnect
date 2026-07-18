package com.careconnect.dto;

/**
 * Strongly-typed appointment extracted by the call summary pipeline.
 *
 * <p>Dates and times are carried as strings rather than {@code LocalDate} or
 * {@code LocalTime} because model output is occasionally sloppy and string
 * carriage round-trips through JSON reliably; downstream consumers parse to
 * typed values where strict validation is required.
 *
 * @param itemId            stable identifier for the item within the summary
 * @param date              appointment date in ISO 8601 {@code yyyy-MM-dd} form
 * @param time              appointment time in {@code HH:mm} form, or null
 * @param with              party the appointment is with (for example,
 *                          {@code "Dr. Patel"})
 * @param purpose           short description of the appointment purpose
 * @param confidence        model confidence in the extracted item, 0.0&ndash;1.0
 * @param sourceTurnId      identifier of the supporting transcript turn
 * @param needsConfirmation user confirmation gate; cleared on explicit confirm
 */
public record SummaryAppointment(
        String itemId,
        String date,
        String time,
        String with,
        String purpose,
        Double confidence,
        String sourceTurnId,
        Boolean needsConfirmation
) {
}
