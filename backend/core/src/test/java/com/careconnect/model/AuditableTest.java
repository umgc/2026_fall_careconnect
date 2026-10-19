package com.careconnect.model;

import org.junit.jupiter.api.Test;

import java.lang.reflect.Method;
import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

class AuditableTest {

    @Test
    void onCreate_setsCreatedAtAndUpdatedAt() throws Exception {
        final ConcreteAuditable entity = new ConcreteAuditable();

        final Method m = Auditable.class.getDeclaredMethod("onCreate");
        m.setAccessible(true);
        m.invoke(entity);

        assertThat(entity.getCreatedAt()).isNotNull();
        assertThat(entity.getUpdatedAt()).isNotNull();
    }

    // ─── onCreate() via @PrePersist ───────────────────────────────────────────

    @Test
    void onUpdate_setsUpdatedAt() throws Exception {
        final ConcreteAuditable entity = new ConcreteAuditable();

        final Method m = Auditable.class.getDeclaredMethod("onUpdate");
        m.setAccessible(true);
        m.invoke(entity);

        assertThat(entity.getUpdatedAt()).isNotNull();
    }

    // ─── onUpdate() via @PreUpdate ────────────────────────────────────────────

    @Test
    void setters_updateFields() throws Exception {
        final ConcreteAuditable entity = new ConcreteAuditable();
        final LocalDateTime created = LocalDateTime.of(2025, 1, 1, 10, 0);
        final LocalDateTime updated = LocalDateTime.of(2025, 6, 1, 12, 0);

        entity.setCreatedAt(created);
        entity.setUpdatedAt(updated);

        assertThat(entity.getCreatedAt()).isEqualTo(created);
        assertThat(entity.getUpdatedAt()).isEqualTo(updated);
    }

    // ─── Setters ──────────────────────────────────────────────────────────────

    @Test
    void defaultConstructor_fieldsAreNull() throws Exception {
        final ConcreteAuditable entity = new ConcreteAuditable();

        assertThat(entity.getCreatedAt()).isNull();
        assertThat(entity.getUpdatedAt()).isNull();
    }

    // ─── Default state ────────────────────────────────────────────────────────

    // Concrete subclass for testing the abstract Auditable
    static class ConcreteAuditable extends Auditable {
    }
}
