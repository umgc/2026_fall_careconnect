package com.careconnect.service;

import com.careconnect.dto.AnswerUpsertRequestDTO;
import com.careconnect.dto.SubmitAnswersRequestDTO;
import com.careconnect.dto.SubmitAnswersResponseDTO;
import com.careconnect.exception.AppException;
import com.careconnect.model.Answer;
import com.careconnect.model.CheckIn;
import com.careconnect.model.CheckInQuestion;
import com.careconnect.model.CheckInQuestionId;
import com.careconnect.model.Patient;
import com.careconnect.model.Question;
import com.careconnect.model.QuestionType;
import com.careconnect.repository.AnswerRepository;
import com.careconnect.repository.CheckInQuestionRepository;
import com.careconnect.repository.CheckInRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AnswerSubmissionServiceTest {

    @Mock
    private CheckInRepository checkInRepository;
    @Mock
    private CheckInQuestionRepository checkInQuestionRepository;
    @Mock
    private AnswerRepository answerRepository;

    private AnswerSubmissionService service;

    @BeforeEach
    void setUp() {
        service = new AnswerSubmissionService(checkInRepository, checkInQuestionRepository, answerRepository);
    }

    @Test
    void submitAnswers_happyPath_persistsAndSetsSubmittedAt() {
        CheckIn checkIn = CheckIn.builder().id(10L).patient(Patient.builder().id(1L).build()).build();
        when(checkInRepository.findById(10L)).thenReturn(Optional.of(checkIn));
        when(checkInQuestionRepository.findByCheckIn_IdOrderByOrdinalAsc(10L)).thenReturn(List.of(
                snapshot(checkIn, 1L, "TEXT", true),
                snapshot(checkIn, 2L, "YES_NO", false),
                snapshot(checkIn, 3L, "NUMBER", true)
        ));
        // Mock empty existing answers (no duplicates)
        when(answerRepository.findByCheckIn_Id(10L)).thenReturn(List.of());

        SubmitAnswersResponseDTO result = service.submitAnswers(10L, new SubmitAnswersRequestDTO(List.of(
                new AnswerUpsertRequestDTO(1L, "all good", null, null),
                new AnswerUpsertRequestDTO(2L, null, true, null),
                new AnswerUpsertRequestDTO(3L, null, null, new BigDecimal("8.5"))
        )));

        assertThat(result.acceptedAnswerCount()).isEqualTo(3);
        assertThat(result.submittedAt()).isNotNull();
        verify(answerRepository).saveAll(any());
        verify(checkInRepository).save(checkIn);
    }

    @Test
    void submitAnswers_rejectsWrongTypedField() {
        CheckIn checkIn = CheckIn.builder().id(10L).patient(Patient.builder().id(1L).build()).build();
        when(checkInRepository.findById(10L)).thenReturn(Optional.of(checkIn));
        when(checkInQuestionRepository.findByCheckIn_IdOrderByOrdinalAsc(10L)).thenReturn(List.of(
                snapshot(checkIn, 1L, "NUMBER", true)
        ));
        when(answerRepository.findByCheckIn_Id(10L)).thenReturn(List.of());

        assertThatThrownBy(() -> service.submitAnswers(10L, new SubmitAnswersRequestDTO(List.of(
                new AnswerUpsertRequestDTO(1L, "not-a-number", null, null)
        )))).isInstanceOf(AppException.class).hasMessageContaining("NUMBER question requires valueNumber");
    }

    @Test
    void submitAnswers_rejectsDuplicateQuestionInRequest() {
        CheckIn checkIn = CheckIn.builder().id(10L).patient(Patient.builder().id(1L).build()).build();
        when(checkInRepository.findById(10L)).thenReturn(Optional.of(checkIn));
        when(checkInQuestionRepository.findByCheckIn_IdOrderByOrdinalAsc(10L)).thenReturn(List.of(
                snapshot(checkIn, 1L, "TEXT", true)
        ));
        when(answerRepository.findByCheckIn_Id(10L)).thenReturn(List.of());

        assertThatThrownBy(() -> service.submitAnswers(10L, new SubmitAnswersRequestDTO(List.of(
                new AnswerUpsertRequestDTO(1L, "first", null, null),
                new AnswerUpsertRequestDTO(1L, "second", null, null)
        )))).isInstanceOf(AppException.class).hasMessageContaining("Duplicate questionId");
    }

    @Test
    void submitAnswers_rejectsMissingRequiredQuestion() {
        CheckIn checkIn = CheckIn.builder().id(10L).patient(Patient.builder().id(1L).build()).build();
        when(checkInRepository.findById(10L)).thenReturn(Optional.of(checkIn));
        when(checkInQuestionRepository.findByCheckIn_IdOrderByOrdinalAsc(10L)).thenReturn(List.of(
                snapshot(checkIn, 1L, "TEXT", true),
                snapshot(checkIn, 2L, "TEXT", true)
        ));
        when(answerRepository.findByCheckIn_Id(10L)).thenReturn(List.of());

        assertThatThrownBy(() -> service.submitAnswers(10L, new SubmitAnswersRequestDTO(List.of(
                new AnswerUpsertRequestDTO(1L, "only one answer", null, null)
        )))).isInstanceOf(AppException.class).hasMessageContaining("Missing required answers");
    }

    @Test
    void submitAnswers_rejectsExistingDuplicateAnswer() {
        CheckIn checkIn = CheckIn.builder().id(10L).patient(Patient.builder().id(1L).build()).build();
        when(checkInRepository.findById(10L)).thenReturn(Optional.of(checkIn));
        when(checkInQuestionRepository.findByCheckIn_IdOrderByOrdinalAsc(10L)).thenReturn(List.of(
                snapshot(checkIn, 1L, "TEXT", true)
        ));
        
        // Mock an existing answer for question 1
        Answer existingAnswer = Answer.builder()
                .checkIn(checkIn)
                .question(Question.builder().id(1L).build())
                .valueText("already there")
                .build();
        when(answerRepository.findByCheckIn_Id(10L)).thenReturn(List.of(existingAnswer));

        assertThatThrownBy(() -> service.submitAnswers(10L, new SubmitAnswersRequestDTO(List.of(
                new AnswerUpsertRequestDTO(1L, "already there", null, null)
        )))).isInstanceOf(AppException.class).hasMessageContaining("Answer already exists");

        verify(answerRepository, never()).saveAll(any());
    }

    @Test
    void submitAnswers_rejectsAlreadySubmittedCheckIn() {
        CheckIn checkIn = CheckIn.builder()
                .id(10L)
                .patient(Patient.builder().id(1L).build())
                .submittedAt(OffsetDateTime.now().minusHours(1))
                .build();
        when(checkInRepository.findById(10L)).thenReturn(Optional.of(checkIn));

        assertThatThrownBy(() -> service.submitAnswers(10L, new SubmitAnswersRequestDTO(List.of(
                new AnswerUpsertRequestDTO(1L, "answer", null, null)
        )))).isInstanceOf(AppException.class)
                .hasMessageContaining("Check-in already submitted");

        verify(checkInQuestionRepository, never()).findByCheckIn_IdOrderByOrdinalAsc(any());
        verify(answerRepository, never()).saveAll(any());
    }

    @Test
    void submitAnswers_handlesRaceConditionOnSave() {
        CheckIn checkIn = CheckIn.builder().id(10L).patient(Patient.builder().id(1L).build()).build();
        when(checkInRepository.findById(10L)).thenReturn(Optional.of(checkIn));
        when(checkInQuestionRepository.findByCheckIn_IdOrderByOrdinalAsc(10L)).thenReturn(List.of(
                snapshot(checkIn, 1L, "TEXT", true)
        ));
        when(answerRepository.findByCheckIn_Id(10L)).thenReturn(List.of());
        // Simulate race condition: concurrent submission violates unique constraint
        when(answerRepository.saveAll(any()))
                .thenThrow(new DataIntegrityViolationException("Duplicate key"));

        assertThatThrownBy(() -> service.submitAnswers(10L, new SubmitAnswersRequestDTO(List.of(
                new AnswerUpsertRequestDTO(1L, "answer", null, null)
        )))).isInstanceOf(AppException.class)
                .hasMessageContaining("Check-in submission conflict");

        verify(checkInRepository, never()).save(any());
    }

    private CheckInQuestion snapshot(CheckIn checkIn, Long questionId, String typeSnapshot, boolean required) {
        Question question = Question.builder()
                .id(questionId)
                .prompt("Q" + questionId)
                .type(QuestionType.valueOf(typeSnapshot))
                .build();
        CheckInQuestion ciq = new CheckInQuestion();
        ciq.setId(new CheckInQuestionId(checkIn.getId(), questionId));
        ciq.setCheckIn(checkIn);
        ciq.setQuestion(question);
        ciq.setRequired(required);
        ciq.setOrdinal(questionId.intValue());
        ciq.setPromptSnapshot("Q" + questionId);
        ciq.setTypeSnapshot(typeSnapshot);
        return ciq;
    }
}
