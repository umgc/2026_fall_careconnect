package com.careconnect.dto;

import com.careconnect.model.Question;

public final class QuestionMapper {

    private QuestionMapper() { }

    public static QuestionDTO toDto(Question q) {
        return new QuestionDTO(
                q.getId(),
                q.getPrompt(),
                q.getType().name(),
                q.isRequired(),
                q.isActive(),
                q.getOrdinal(),
                q.getFormKey(),
                q.getFormVersion(),
                q.getSectionKey(),
                q.getFieldKey(),
                q.getScoreWeight()
        );
    }

    public static void applyUpsert(Question target, QuestionUpsertDTO src) {
        target.setPrompt(src.prompt());
        target.setType(src.type());
        target.setRequired(src.required());
        target.setOrdinal(src.ordinal());
        if (src.formKey() != null) target.setFormKey(src.formKey());
        if (src.formVersion() != null) target.setFormVersion(src.formVersion());
        if (src.sectionKey() != null) target.setSectionKey(src.sectionKey());
        if (src.fieldKey() != null) target.setFieldKey(src.fieldKey());
        target.setScoreWeight(src.scoreWeight() == null ? null : java.math.BigDecimal.valueOf(src.scoreWeight()));
    }
}
