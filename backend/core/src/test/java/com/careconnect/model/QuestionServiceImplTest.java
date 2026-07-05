package com.careconnect.model;

import com.careconnect.dto.QuestionDTO;
import com.careconnect.dto.QuestionUpsertDTO;
import com.careconnect.repository.QuestionRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class QuestionServiceImplTest {

    @Mock
    private QuestionRepository repo;

    @InjectMocks
    private QuestionServiceImpl service;

    // ─── listQuestions(null) – all questions ──────────────────────────────────

    @Test
    void listQuestions_nullActive_returnsAllOrderedByOrdinal() throws Exception {
        final Question q1 = Question.builder().id(1L).prompt("Q1").type(QuestionType.TEXT)
                .active(true).ordinal(1).build();
        final Question q2 = Question.builder().id(2L).prompt("Q2").type(QuestionType.YES_NO)
                .active(false).ordinal(2).build();
        when(repo.findAllByOrderByOrdinalAsc()).thenReturn(List.of(q1, q2));

        final List<QuestionDTO> result = service.listQuestions(null);

        assertThat(result).hasSize(2);
        assertThat(result.get(0).prompt()).isEqualTo("Q1");
        assertThat(result.get(1).prompt()).isEqualTo("Q2");
        verify(repo).findAllByOrderByOrdinalAsc();
    }

    // ─── listQuestions(true) – active only ────────────────────────────────────

    @Test
    void listQuestions_trueActive_returnsActiveOnlyOrdered() throws Exception {
        final Question q = Question.builder().id(1L).prompt("Active Q").type(QuestionType.TEXT)
                .active(true).ordinal(1).build();
        when(repo.findAllByActiveTrueOrderByOrdinalAsc()).thenReturn(List.of(q));

        final List<QuestionDTO> result = service.listQuestions(true);

        assertThat(result).hasSize(1);
        assertThat(result.get(0).active()).isTrue();
        verify(repo).findAllByActiveTrueOrderByOrdinalAsc();
    }

    // ─── listQuestions(false) – inactive only ────────────────────────────────

    @Test
    void listQuestions_falseActive_returnsInactiveOnlyOrdered() throws Exception {
        final Question q = Question.builder().id(2L).prompt("Inactive Q").type(QuestionType.YES_NO)
                .active(false).ordinal(3).build();
        when(repo.findAllByActiveFalseOrderByOrdinalAsc()).thenReturn(List.of(q));

        final List<QuestionDTO> result = service.listQuestions(false);

        assertThat(result).hasSize(1);
        assertThat(result.get(0).active()).isFalse();
        verify(repo).findAllByActiveFalseOrderByOrdinalAsc();
    }

    // ─── findActiveOrdered() ─────────────────────────────────────────────────

    @Test
    void findActiveOrdered_returnsActiveMappedToDtos() throws Exception {
        final Question q = Question.builder().id(3L).prompt("Active?").type(QuestionType.TRUE_FALSE)
                .active(true).ordinal(2).build();
        when(repo.findAllByActiveTrueOrderByOrdinalAsc()).thenReturn(List.of(q));

        final List<QuestionDTO> result = service.findActiveOrdered();

        assertThat(result).hasSize(1);
        assertThat(result.get(0).id()).isEqualTo(3L);
        assertThat(result.get(0).type()).isEqualTo("TRUE_FALSE");
        verify(repo).findAllByActiveTrueOrderByOrdinalAsc();
    }

    // ─── getOne() – found ─────────────────────────────────────────────────────

    @Test
    void getOne_existingId_returnsDto() throws Exception {
        final Question q = Question.builder().id(5L).prompt("Pain level?").type(QuestionType.NUMBER)
                .active(true).ordinal(0).build();
        when(repo.findById(5L)).thenReturn(Optional.of(q));

        final Optional<QuestionDTO> result = service.getOne(5L);

        assertThat(result).isPresent();
        assertThat(result.get().id()).isEqualTo(5L);
        assertThat(result.get().prompt()).isEqualTo("Pain level?");
    }

    // ─── getOne() – not found ─────────────────────────────────────────────────

    @Test
    void getOne_nonExistingId_returnsEmpty() throws Exception {
        when(repo.findById(99L)).thenReturn(Optional.empty());

        final Optional<QuestionDTO> result = service.getOne(99L);

        assertThat(result).isEmpty();
    }

    // ─── create() – no conflict ───────────────────────────────────────────────

    @Test
    void create_noConflict_savesWithoutShifting() throws Exception {
        // Arrange
        final QuestionUpsertDTO body = new QuestionUpsertDTO("How do you feel?", QuestionType.TEXT, false, 1);
        when(repo.existsByOrdinalAndIdNot(1, Long.MAX_VALUE)).thenReturn(false);
        final Question saved = Question.builder().id(10L).prompt("How do you feel?")
                .type(QuestionType.TEXT).required(false).active(true).ordinal(1).build();
        when(repo.save(any(Question.class))).thenReturn(saved);

        // Act
        final QuestionDTO result = service.create(body);

        // Assert
        assertThat(result.id()).isEqualTo(10L);
        assertThat(result.active()).isTrue();
        verify(repo, never()).shiftOrdinalsUp(anyInt(), anyLong());
        verify(repo).save(any(Question.class));
    }

    @Test
    void create_ordinalConflict_shiftsExistingQuestionsUp() throws Exception {
        // Arrange – ordinal 2 is already taken
        final QuestionUpsertDTO body = new QuestionUpsertDTO("New Q?", QuestionType.TEXT, false, 2);
        when(repo.existsByOrdinalAndIdNot(2, Long.MAX_VALUE)).thenReturn(true);
        final Question saved = Question.builder().id(11L).prompt("New Q?")
                .type(QuestionType.TEXT).active(true).ordinal(2).build();
        when(repo.save(any(Question.class))).thenReturn(saved);

        // Act
        service.create(body);

        // Assert – shift was triggered
        verify(repo).shiftOrdinalsUp(2, Long.MAX_VALUE);
        verify(repo).save(any(Question.class));
    }

    // ─── update() – no ordinal change ────────────────────────────────────────

    @Test
    void update_existingId_sameOrdinal_noShift() throws Exception {
        // Arrange – ordinal unchanged (0 → 0)
        final QuestionUpsertDTO body = new QuestionUpsertDTO("Updated prompt?", QuestionType.YES_NO, true, 0);
        final Question existing = Question.builder().id(7L).prompt("Old prompt?")
                .type(QuestionType.TEXT).active(true).ordinal(0).build();
        final Question updated = Question.builder().id(7L).prompt("Updated prompt?")
                .type(QuestionType.YES_NO).required(true).active(true).ordinal(0).build();
        when(repo.findById(7L)).thenReturn(Optional.of(existing));
        when(repo.save(any(Question.class))).thenReturn(updated);

        // Act
        final Optional<QuestionDTO> result = service.update(7L, body);

        // Assert
        assertThat(result).isPresent();
        assertThat(result.get().prompt()).isEqualTo("Updated prompt?");
        verify(repo, never()).shiftOrdinalsUp(anyInt(), anyLong());
    }

    @Test
    void update_existingId_ordinalChanges_conflictExists_shiftsUp() throws Exception {
        // Arrange – ordinal changes from 0 to 2, and 2 is taken
        final QuestionUpsertDTO body = new QuestionUpsertDTO("Updated prompt?", QuestionType.YES_NO, true, 2);
        final Question existing = Question.builder().id(7L).prompt("Old prompt?")
                .type(QuestionType.TEXT).active(true).ordinal(0).build();
        final Question updated = Question.builder().id(7L).prompt("Updated prompt?")
                .type(QuestionType.YES_NO).required(true).active(true).ordinal(2).build();
        when(repo.findById(7L)).thenReturn(Optional.of(existing));
        when(repo.existsByOrdinalAndIdNot(2, 7L)).thenReturn(true);
        when(repo.save(any(Question.class))).thenReturn(updated);

        // Act
        service.update(7L, body);

        // Assert
        verify(repo).shiftOrdinalsUp(2, 7L);
    }

    @Test
    void update_existingId_ordinalChanges_noConflict_noShift() throws Exception {
        // Arrange – ordinal changes from 0 to 3, but 3 is free
        final QuestionUpsertDTO body = new QuestionUpsertDTO("Updated?", QuestionType.TEXT, false, 3);
        final Question existing = Question.builder().id(8L).prompt("Q?")
                .type(QuestionType.TEXT).active(true).ordinal(0).build();
        final Question updated = Question.builder().id(8L).prompt("Updated?")
                .type(QuestionType.TEXT).active(true).ordinal(3).build();
        when(repo.findById(8L)).thenReturn(Optional.of(existing));
        when(repo.existsByOrdinalAndIdNot(3, 8L)).thenReturn(false);
        when(repo.save(any(Question.class))).thenReturn(updated);

        // Act
        service.update(8L, body);

        // Assert
        verify(repo, never()).shiftOrdinalsUp(anyInt(), anyLong());
    }

    // ─── update() – not found ────────────────────────────────────────────────

    @Test
    void update_nonExistingId_returnsEmpty() throws Exception {
        final QuestionUpsertDTO body = new QuestionUpsertDTO("X", QuestionType.TEXT, false, 0);
        when(repo.findById(99L)).thenReturn(Optional.empty());

        final Optional<QuestionDTO> result = service.update(99L, body);

        assertThat(result).isEmpty();
    }

    // ─── setActive() – found ─────────────────────────────────────────────────

    @Test
    void setActive_existingId_updatesActiveFlag() throws Exception {
        final Question existing = Question.builder().id(4L).prompt("Q?")
                .type(QuestionType.TEXT).active(true).ordinal(0).build();
        final Question deactivated = Question.builder().id(4L).prompt("Q?")
                .type(QuestionType.TEXT).active(false).ordinal(0).build();

        when(repo.findById(4L)).thenReturn(Optional.of(existing));
        when(repo.save(any(Question.class))).thenReturn(deactivated);

        final Optional<QuestionDTO> result = service.setActive(4L, false);

        assertThat(result).isPresent();
        assertThat(result.get().active()).isFalse();
        verify(repo).save(any(Question.class));
    }

    // ─── setActive() – not found ──────────────────────────────────────────────

    @Test
    void setActive_nonExistingId_returnsEmpty() throws Exception {
        when(repo.findById(99L)).thenReturn(Optional.empty());

        final Optional<QuestionDTO> result = service.setActive(99L, true);

        assertThat(result).isEmpty();
    }
}
