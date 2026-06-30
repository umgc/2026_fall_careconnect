package com.careconnect.model.confirmation;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class ConfirmationItemTest {

    private static final Long RESOLVER_ID = 20L;

    @Test
    void builderDefaultsStatusToPending() {
        ConfirmationItem item = ConfirmationItem.builder()
                .sourceType(ConfirmationSourceType.ASK_AI)
                .payload("{}")
                .requestedBy(1L)
                .build();

        assertThat(item.getStatus()).isEqualTo(ConfirmationStatus.PENDING);
    }

    @Test
    void confirm_setsAllResolutionFields() {
        ConfirmationItem item = buildPending();

        item.confirm(RESOLVER_ID, "Looks correct");

        assertThat(item.getStatus()).isEqualTo(ConfirmationStatus.CONFIRMED);
        assertThat(item.getResolvedBy()).isEqualTo(RESOLVER_ID);
        assertThat(item.getResolvedAt()).isNotNull();
        assertThat(item.getResolutionNote()).isEqualTo("Looks correct");
        assertThat(item.getUpdatedAt()).isNotNull();
    }

    @Test
    void dismiss_setsAllResolutionFields() {
        ConfirmationItem item = buildPending();

        item.dismiss(RESOLVER_ID, "Inaccurate");

        assertThat(item.getStatus()).isEqualTo(ConfirmationStatus.DISMISSED);
        assertThat(item.getResolvedBy()).isEqualTo(RESOLVER_ID);
        assertThat(item.getResolvedAt()).isNotNull();
        assertThat(item.getResolutionNote()).isEqualTo("Inaccurate");
        assertThat(item.getUpdatedAt()).isNotNull();
    }

    @Test
    void confirm_withNullNote_leavesNoteNull() {
        ConfirmationItem item = buildPending();

        item.confirm(RESOLVER_ID, null);

        assertThat(item.getStatus()).isEqualTo(ConfirmationStatus.CONFIRMED);
        assertThat(item.getResolutionNote()).isNull();
    }

    @Test
    void dismiss_withNullNote_leavesNoteNull() {
        ConfirmationItem item = buildPending();

        item.dismiss(RESOLVER_ID, null);

        assertThat(item.getStatus()).isEqualTo(ConfirmationStatus.DISMISSED);
        assertThat(item.getResolutionNote()).isNull();
    }

    @Test
    void onCreate_setsTimestamps() {
        ConfirmationItem item = buildPending();
        assertThat(item.getCreatedAt()).isNull();
        assertThat(item.getUpdatedAt()).isNull();

        item.onCreate();

        assertThat(item.getCreatedAt()).isNotNull();
        assertThat(item.getUpdatedAt()).isNotNull();
    }

    @Test
    void onUpdate_setsUpdatedAt() {
        ConfirmationItem item = buildPending();
        item.onCreate();
        var originalUpdatedAt = item.getUpdatedAt();

        item.onUpdate();

        assertThat(item.getUpdatedAt()).isNotNull();
        assertThat(item.getUpdatedAt()).isAfterOrEqualTo(originalUpdatedAt);
    }

    @Test
    void confirm_updatesTimestampAfterOnCreate() {
        ConfirmationItem item = buildPending();
        item.onCreate();
        var createdAt = item.getCreatedAt();

        item.confirm(RESOLVER_ID, "ok");

        assertThat(item.getCreatedAt()).isEqualTo(createdAt);
        assertThat(item.getUpdatedAt()).isAfterOrEqualTo(createdAt);
    }

    private ConfirmationItem buildPending() {
        return ConfirmationItem.builder()
                .sourceType(ConfirmationSourceType.SUMMARY)
                .payload("{\"headline\":\"test\"}")
                .requestedBy(1L)
                .build();
    }
}
