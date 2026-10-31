package com.careconnect.service;

import com.careconnect.model.CallAttendee;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * The time window of a call recording that belongs to each attendee row (one row per Chime join).
 *
 * <p>KVS pool streams are reused across calls, so audio may only be read from a stream between
 * that row's join and leave, inside the recording. A user who rejoined has several rows; each
 * window ends at the user's next join, so windows never overlap and no speech is read twice.</p>
 */
public final class AttendeeAudioWindows {

    /**
     * One attendee row's window, in UTC.
     *
     * @param attendee the attendee row the window belongs to
     * @param from window start (inclusive)
     * @param to window end (exclusive), always after {@code from}
     */
    public record Window(CallAttendee attendee, LocalDateTime from, LocalDateTime to) {

        /** Window start as an instant. */
        public Instant fromInstant() {
            return from.toInstant(ZoneOffset.UTC);
        }

        /** Window end as an instant. */
        public Instant toInstant() {
            return to.toInstant(ZoneOffset.UTC);
        }
    }

    private AttendeeAudioWindows() {
    }

    /**
     * Windows for every user's rows, each user's windows made consecutive, ordered by start.
     *
     * @param rows attendee rows of one call (rows without a user id are ignored)
     * @param recordingStart recording start (UTC)
     * @param recordingEnd recording end (UTC)
     */
    public static List<Window> forCall(
            final List<CallAttendee> rows,
            final LocalDateTime recordingStart,
            final LocalDateTime recordingEnd) {
        final Map<Long, List<CallAttendee>> byUser = new LinkedHashMap<>();
        for (final CallAttendee row : rows) {
            if (row.getUserId() != null) {
                byUser.computeIfAbsent(row.getUserId(), id -> new ArrayList<>()).add(row);
            }
        }
        final List<Window> windows = new ArrayList<>();
        for (final List<CallAttendee> userRows : byUser.values()) {
            windows.addAll(forUser(userRows, recordingStart, recordingEnd));
        }
        windows.sort(Comparator.comparing(Window::from));
        return windows;
    }

    /**
     * Windows for one user's rows, in join order: each clamped to its join/leave (a missing leave
     * means the recording end) and to the recording, and ended by the user's next join — joining
     * again means the previous session is over, even when its leave was recorded late or never.
     * Rows left with no time are dropped.
     *
     * @param rows attendee rows of one user in one call
     * @param recordingStart recording start (UTC)
     * @param recordingEnd recording end (UTC)
     */
    public static List<Window> forUser(
            final List<CallAttendee> rows,
            final LocalDateTime recordingStart,
            final LocalDateTime recordingEnd) {
        final List<CallAttendee> ordered = rows.stream()
                .sorted(Comparator.comparing(
                        CallAttendee::getJoinedAt, Comparator.nullsFirst(Comparator.naturalOrder())))
                .toList();
        final List<Window> windows = new ArrayList<>();
        for (int i = 0; i < ordered.size(); i++) {
            final CallAttendee row = ordered.get(i);
            final LocalDateTime from = later(row.getJoinedAt(), recordingStart);
            LocalDateTime to = earlier(row.getLeftAt(), recordingEnd);
            if (i + 1 < ordered.size()) {
                to = earlier(ordered.get(i + 1).getJoinedAt(), to);
            }
            if (to.isAfter(from)) {
                windows.add(new Window(row, from, to));
            }
        }
        return windows;
    }

    /** The later of two times; a null {@code a} yields {@code b}. */
    private static LocalDateTime later(final LocalDateTime a, final LocalDateTime b) {
        return a == null || a.isBefore(b) ? b : a;
    }

    /** The earlier of two times; a null {@code a} yields {@code b}. */
    private static LocalDateTime earlier(final LocalDateTime a, final LocalDateTime b) {
        return a == null || a.isAfter(b) ? b : a;
    }
}
