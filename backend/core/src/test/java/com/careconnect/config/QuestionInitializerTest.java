package com.careconnect.config;

import com.careconnect.model.Question;
import com.careconnect.model.QuestionType;
import com.careconnect.repository.QuestionRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/**
 * Unit tests for {@link QuestionInitializer}.
 * <p>
 * QuestionInitializer is a Spring {@code @Component} that seeds the database with
 * a fixed set of health-check questions on application startup. It is idempotent:
 * if questions already exist ({@code repository.count() > 0}), it does nothing.
 * <p>
 * Mockito is used here via {@code @Mock} and {@code @InjectMocks} annotations so that
 * the real {@link QuestionRepository} is replaced with a mock, avoiding the need for a
 * database. {@link ArgumentCaptor} is used in several tests to capture the {@link Question}
 * objects passed to {@code save()}, allowing assertions on their field values.
 */
class QuestionInitializerTest {

    @Mock
    private QuestionRepository questionRepository;

    @InjectMocks
    private QuestionInitializer questionInitializer;

    @BeforeEach
    void setUp() throws Exception {
        // Initialize @Mock and @InjectMocks fields so Mockito wires them before each test.
        MockitoAnnotations.openMocks(this);
    }

    @Test
    void initQuestions_DoesNothingIfQuestionsExist() throws Exception {
        // Verifies the idempotency guard: when the repository already holds questions
        // (count > 0), no save calls are made and the count is checked exactly once.
        when(questionRepository.count()).thenReturn(5L);

        questionInitializer.initQuestions();

        verify(questionRepository, never()).save(any(Question.class));
        verify(questionRepository, times(1)).count();
    }

    @Test
    void initQuestions_CreatesAllQuestionsWhenEmpty() throws Exception {
        // Verifies that exactly 15 questions are persisted when the table is empty.
        // The count is expected to be called at least twice (before and after seeding).
        when(questionRepository.count()).thenReturn(0L);
        when(questionRepository.save(any(Question.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        questionInitializer.initQuestions();

        verify(questionRepository, times(15)).save(any(Question.class));
        verify(questionRepository, atLeast(2)).count(); // before and after
    }

    @Test
    void initQuestions_SavesCorrectFirstQuestion() throws Exception {
        // Uses ArgumentCaptor to capture all saved Question objects so the first one
        // can be inspected for correct prompt text, type, required/active flags, and
        // ordinal (display order). This pins the first seed question's exact definition.
        when(questionRepository.count()).thenReturn(0L);

        final ArgumentCaptor<Question> captor = ArgumentCaptor.forClass(Question.class);
        when(questionRepository.save(captor.capture()))
                .thenAnswer(invocation -> invocation.getArgument(0));

        questionInitializer.initQuestions();

        final List<Question> saved = captor.getAllValues();

        final Question first = saved.get(0);

        assertEquals("Did you take all of your prescribed medications today?", first.getPrompt());
        assertEquals(QuestionType.YES_NO, first.getType());
        assertTrue(first.isRequired());
        assertTrue(first.isActive());
        assertEquals(1, first.getOrdinal());
    }

    @Test
    void initQuestions_AllOrdinalsAreSequential() throws Exception {
        // Verifies that all 15 questions are assigned sequential ordinals starting at 1,
        // which controls the display order presented to the user in the health-check form.
        when(questionRepository.count()).thenReturn(0L);

        final ArgumentCaptor<Question> captor = ArgumentCaptor.forClass(Question.class);
        when(questionRepository.save(captor.capture()))
                .thenAnswer(invocation -> invocation.getArgument(0));

        questionInitializer.initQuestions();

        final List<Question> saved = captor.getAllValues();

        assertEquals(15, saved.size());

        for (int i = 0; i < saved.size(); i++) {
            assertEquals(i + 1, saved.get(i).getOrdinal());
        }
    }

    @Test
    void initQuestions_ContinuesIfSaveThrows() throws Exception {
        // Verifies that a database error on save does not abort the initializer: all 15
        // save attempts are still made even if each one throws, and no exception escapes
        // to the caller (which would prevent the application from starting).
        when(questionRepository.count()).thenReturn(0L);

        when(questionRepository.save(any(Question.class)))
                .thenThrow(new RuntimeException("DB failure"));

        assertDoesNotThrow(() -> questionInitializer.initQuestions());

        verify(questionRepository, times(15)).save(any(Question.class));
    }

    @Test
    void initQuestions_HandlesCountExceptionGracefully() throws Exception {
        // Verifies that if the count query itself fails (e.g. Flyway has not yet run),
        // the initializer catches the exception, skips seeding entirely, and does not
        // propagate an exception that would crash the application context startup.
        when(questionRepository.count())
                .thenThrow(new RuntimeException("Database unavailable"));

        assertDoesNotThrow(() -> questionInitializer.initQuestions());

        verify(questionRepository, times(1)).count();
        verify(questionRepository, never()).save(any());
    }

    @Test
    void initQuestions_CreatesAllExpectedQuestionTypes() throws Exception {
        // Verifies that the seed data includes at least one question of each expected
        // QuestionType (YES_NO, TRUE_FALSE, NUMBER, TEXT), confirming the initializer
        // covers all answer formats used by the health-check questionnaire.
        when(questionRepository.count()).thenReturn(0L);

        final ArgumentCaptor<Question> captor = ArgumentCaptor.forClass(Question.class);
        when(questionRepository.save(captor.capture()))
                .thenAnswer(invocation -> invocation.getArgument(0));

        questionInitializer.initQuestions();

        final List<Question> saved = captor.getAllValues();

        final long yesNoCount = saved.stream()
                .filter(q -> q.getType() == QuestionType.YES_NO)
                .count();

        final long trueFalseCount = saved.stream()
                .filter(q -> q.getType() == QuestionType.TRUE_FALSE)
                .count();

        final long numberCount = saved.stream()
                .filter(q -> q.getType() == QuestionType.NUMBER)
                .count();

        final long textCount = saved.stream()
                .filter(q -> q.getType() == QuestionType.TEXT)
                .count();

        assertTrue(yesNoCount > 0);
        assertTrue(trueFalseCount > 0);
        assertTrue(numberCount > 0);
        assertTrue(textCount > 0);
    }
}
