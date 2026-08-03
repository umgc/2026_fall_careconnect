package com.careconnect.model;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;

import static org.assertj.core.api.Assertions.assertThat;

class CheckInQuestionTest {

    // ─── Default constructor ──────────────────────────────────────────────────

    @Test
    void defaultConstructor_createsInstance() throws Exception {
        final CheckInQuestion cq = new CheckInQuestion();
        assertThat(cq).isNotNull();
        assertThat(cq.getId()).isNull();
        assertThat(cq.getCheckIn()).isNull();
        assertThat(cq.getQuestion()).isNull();
    }

    // ─── Parameterized constructor ────────────────────────────────────────────

    @Test
    void parameterizedConstructor_setsFields() throws Exception {
        final CheckIn checkIn = CheckIn.builder().id(1L).build();
        final Question question = Question.builder()
                .id(2L)
                .prompt("How are you?")
                .type(QuestionType.TEXT)
                .formKey("comprehensive-assessment")
                .formVersion(1)
                .sectionKey("mental_wellness")
                .fieldKey("how_are_you_today")
                .scoreWeight(BigDecimal.valueOf(1.5))
                .build();

        final CheckInQuestion cq = new CheckInQuestion(
                checkIn, question, true, 1, "How are you?", "TEXT",
                "comprehensive-assessment", 1, "mental_wellness", "how_are_you_today", BigDecimal.valueOf(1.5)
        );

        assertThat(cq.getCheckIn()).isSameAs(checkIn);
        assertThat(cq.getQuestion()).isSameAs(question);
        assertThat(cq.isRequired()).isTrue();
        assertThat(cq.getOrdinal()).isEqualTo(1);
        assertThat(cq.getPromptSnapshot()).isEqualTo("How are you?");
        assertThat(cq.getTypeSnapshot()).isEqualTo("TEXT");
        assertThat(cq.getFormKeySnapshot()).isEqualTo("comprehensive-assessment");
        assertThat(cq.getFormVersionSnapshot()).isEqualTo(1);
        assertThat(cq.getSectionKeySnapshot()).isEqualTo("mental_wellness");
        assertThat(cq.getFieldKeySnapshot()).isEqualTo("how_are_you_today");
        assertThat(cq.getScoreWeightSnapshot()).isEqualByComparingTo("1.5");
        assertThat(cq.getId()).isNotNull();
        assertThat(cq.getId().getCheckInId()).isEqualTo(1L);
        assertThat(cq.getId().getQuestionId()).isEqualTo(2L);
    }

    // ─── Setters ──────────────────────────────────────────────────────────────

    @Test
    void setters_updateFields() throws Exception {
        final CheckInQuestion cq = new CheckInQuestion();
        final CheckInQuestionId embeddedId = new CheckInQuestionId(5L, 10L);
        final CheckIn checkIn = new CheckIn();
        final Question question = new Question();

        cq.setId(embeddedId);
        cq.setCheckIn(checkIn);
        cq.setQuestion(question);
        cq.setRequired(false);
        cq.setOrdinal(3);
        cq.setPromptSnapshot("snapshot prompt");
        cq.setTypeSnapshot("YES_NO");
        cq.setFormKeySnapshot("virtual-checkin");
        cq.setFormVersionSnapshot(1);
        cq.setSectionKeySnapshot("general");
        cq.setFieldKeySnapshot("safety_question");
        cq.setScoreWeightSnapshot(BigDecimal.ONE);

        assertThat(cq.getId()).isSameAs(embeddedId);
        assertThat(cq.getCheckIn()).isSameAs(checkIn);
        assertThat(cq.getQuestion()).isSameAs(question);
        assertThat(cq.isRequired()).isFalse();
        assertThat(cq.getOrdinal()).isEqualTo(3);
        assertThat(cq.getPromptSnapshot()).isEqualTo("snapshot prompt");
        assertThat(cq.getTypeSnapshot()).isEqualTo("YES_NO");
        assertThat(cq.getFormKeySnapshot()).isEqualTo("virtual-checkin");
        assertThat(cq.getFormVersionSnapshot()).isEqualTo(1);
        assertThat(cq.getSectionKeySnapshot()).isEqualTo("general");
        assertThat(cq.getFieldKeySnapshot()).isEqualTo("safety_question");
        assertThat(cq.getScoreWeightSnapshot()).isEqualByComparingTo("1");
    }
}
