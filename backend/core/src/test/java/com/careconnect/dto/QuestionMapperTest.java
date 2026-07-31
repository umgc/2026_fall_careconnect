package com.careconnect.dto;

import com.careconnect.model.Question;
import com.careconnect.model.QuestionType;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.lang.reflect.Constructor;
import java.lang.reflect.Modifier;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class QuestionMapperTest {

    @Mock
    private Question mockQuestion;

    // ─── Private constructor ──────────────────────────────────────────────────

    @Test
    void constructor_isPrivate() throws Exception {
        final Constructor<QuestionMapper> constructor = QuestionMapper.class.getDeclaredConstructor();
        assertThat(Modifier.isPrivate(constructor.getModifiers())).isTrue();
        constructor.setAccessible(true);
        constructor.newInstance(); // covers the private constructor line
    }

    // ─── toDto() ──────────────────────────────────────────────────────────────

    @Test
    void toDto_mapsAllFieldsCorrectly() throws Exception {
        when(mockQuestion.getId()).thenReturn(1L);
        when(mockQuestion.getPrompt()).thenReturn("How are you feeling?");
        when(mockQuestion.getType()).thenReturn(QuestionType.TEXT);
        when(mockQuestion.isRequired()).thenReturn(true);
        when(mockQuestion.isActive()).thenReturn(true);
        when(mockQuestion.getOrdinal()).thenReturn(3);

        final QuestionDTO dto = QuestionMapper.toDto(mockQuestion);

        assertThat(dto.id()).isEqualTo(1L);
        assertThat(dto.prompt()).isEqualTo("How are you feeling?");
        assertThat(dto.type()).isEqualTo("TEXT");
        assertThat(dto.required()).isTrue();
        assertThat(dto.active()).isTrue();
        assertThat(dto.ordinal()).isEqualTo(3);
    }

    @Test
    void toDto_yesNoType_convertsToString() throws Exception {
        when(mockQuestion.getId()).thenReturn(2L);
        when(mockQuestion.getPrompt()).thenReturn("Did you sleep well?");
        when(mockQuestion.getType()).thenReturn(QuestionType.YES_NO);
        when(mockQuestion.isRequired()).thenReturn(false);
        when(mockQuestion.isActive()).thenReturn(false);
        when(mockQuestion.getOrdinal()).thenReturn(1);

        final QuestionDTO dto = QuestionMapper.toDto(mockQuestion);

        assertThat(dto.type()).isEqualTo("YES_NO");
        assertThat(dto.required()).isFalse();
        assertThat(dto.active()).isFalse();
    }

    // ─── applyUpsert() ────────────────────────────────────────────────────────

    @Test
    void applyUpsert_setsAllFieldsOnTarget() throws Exception {
        final QuestionUpsertDTO src = new QuestionUpsertDTO(
                "Rate your pain 1-10", QuestionType.NUMBER, true, 5);

        QuestionMapper.applyUpsert(mockQuestion, src);

        verify(mockQuestion).setPrompt("Rate your pain 1-10");
        verify(mockQuestion).setType(QuestionType.NUMBER);
        verify(mockQuestion).setRequired(true);
        verify(mockQuestion).setOrdinal(5);
    }

}
