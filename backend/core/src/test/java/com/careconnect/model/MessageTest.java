package com.careconnect.model;

import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

class MessageTest {

    // ─── Default constructor ──────────────────────────────────────────────────

    @Test
    void defaultConstructor_createsInstance() throws Exception {
        final Message msg = new Message();

        assertThat(msg).isNotNull();
        assertThat(msg.getId()).isNull();
        assertThat(msg.getSenderId()).isNull();
        assertThat(msg.getReceiverId()).isNull();
        assertThat(msg.getContent()).isNull();
        assertThat(msg.getTimestamp()).isNull();
        assertThat(msg.isRead()).isFalse();
    }

    // ─── 3-arg constructor ────────────────────────────────────────────────────

    @Test
    void threeArgConstructor_setsFields() throws Exception {
        final Message msg = new Message(1L, 2L, "Hello there!");

        assertThat(msg.getSenderId()).isEqualTo(1L);
        assertThat(msg.getReceiverId()).isEqualTo(2L);
        assertThat(msg.getContent()).isEqualTo("Hello there!");
        assertThat(msg.getTimestamp()).isNotNull();
        assertThat(msg.isRead()).isFalse();
    }

    // ─── Setters / Getters ────────────────────────────────────────────────────

    @Test
    void shareFields_defaultToNull_andRoundTrip() {
        final Message msg = new Message(1L, 2L, "Shared my Medicare records");

        assertThat(msg.getShareKind()).isNull();
        assertThat(msg.getSharePatientId()).isNull();

        msg.setShareKind(Message.ShareKind.MEDICARE);
        msg.setSharePatientId(10L);

        assertThat(msg.getShareKind()).isEqualTo(Message.ShareKind.MEDICARE);
        assertThat(msg.getSharePatientId()).isEqualTo(10L);
    }

    @Test
    void settersAndGetters_updateFields() throws Exception {
        final Message msg = new Message();
        final LocalDateTime now = LocalDateTime.now();

        msg.setSenderId(10L);
        msg.setReceiverId(20L);
        msg.setContent("How are you?");
        msg.setTimestamp(now);
        msg.setRead(true);

        assertThat(msg.getSenderId()).isEqualTo(10L);
        assertThat(msg.getReceiverId()).isEqualTo(20L);
        assertThat(msg.getContent()).isEqualTo("How are you?");
        assertThat(msg.getTimestamp()).isEqualTo(now);
        assertThat(msg.isRead()).isTrue();
    }
}
