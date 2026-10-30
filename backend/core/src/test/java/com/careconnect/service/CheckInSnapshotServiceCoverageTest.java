package com.careconnect.service;

import com.careconnect.dto.CheckInDetailDTO;
import com.careconnect.dto.CheckInPageDTO;
import com.careconnect.exception.AppException;
import com.careconnect.model.Answer;
import com.careconnect.model.CheckIn;
import com.careconnect.model.CheckInQuestion;
import com.careconnect.model.Patient;
import com.careconnect.model.Question;
import com.careconnect.model.User;
import com.careconnect.repository.AnswerRepository;
import com.careconnect.repository.CheckInQuestionRepository;
import com.careconnect.repository.CheckInRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.QuestionRepository;
import com.careconnect.security.Role;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class CheckInSnapshotServiceCoverageTest {

    @Mock private CheckInRepository checkInRepository;
    @Mock private CheckInQuestionRepository checkInQuestionRepository;
    @Mock private AnswerRepository answerRepository;
    @Mock private PatientRepository patientRepository;
    @Mock private QuestionRepository questionRepository;

    private CheckInSnapshotService service;
    private final Patient patient = Patient.builder().id(8L).build();

    @BeforeEach
    void setUp() {
        service = new CheckInSnapshotService(checkInRepository, checkInQuestionRepository, answerRepository,
                patientRepository, questionRepository);
        when(patientRepository.existsById(8L)).thenReturn(true);
        when(patientRepository.existsById(9L)).thenReturn(false);
        when(checkInQuestionRepository.countByCheckInIds(any())).thenReturn(List.of());
    }

    @Test
    void filteredListingNormalizesInputs() {
        CheckIn c = CheckIn.builder().id(1L).patient(patient).submittedAt(OffsetDateTime.now()).build();
        when(checkInRepository.findByPatientIdWithFilters(eq(8L), any(), any(), any(), any()))
                .thenReturn(new PageImpl<>(List.of(c), PageRequest.of(0, 20), 1));
        CheckInPageDTO page = service.listCheckInsForPatientFiltered(8L, " Submitted ", LocalDate.of(2026, 1, 1),
                LocalDate.of(2026, 2, 1), -1, 500);
        assertThat(page).isNotNull();
        assertThat(service.listCheckInsForPatientFiltered(8L, null, null, null, null, null)).isNotNull();
        assertThat(service.listCheckInsForPatientFiltered(8L, " ", null, null, 1, 0)).isNotNull();

        assertThatThrownBy(() -> service.listCheckInsForPatientFiltered(8L, "bogus", null, null, null, null))
                .isInstanceOf(AppException.class);
        assertThatThrownBy(() -> service.listCheckInsForPatientFiltered(8L, null, LocalDate.of(2026, 3, 1),
                LocalDate.of(2026, 1, 1), null, null)).isInstanceOf(AppException.class);
        assertThatThrownBy(() -> service.listCheckInsForPatientFiltered(9L, null, null, null, null, null))
                .isInstanceOf(AppException.class);
        assertThatThrownBy(() -> service.listCheckInsForPatient(9L)).isInstanceOf(AppException.class);
        assertThatThrownBy(() -> service.getLatestCheckInForPatient(9L)).isInstanceOf(AppException.class);
    }

    @Test
    void reviewBuildsDetailWithAnswers() {
        Question q1 = Question.builder().id(1L).build();
        Question q2 = Question.builder().id(2L).build();
        CheckInQuestion s1 = new CheckInQuestion();
        s1.setQuestion(q1);
        s1.setPromptSnapshot("How are you?");
        CheckInQuestion s2 = new CheckInQuestion();
        s2.setQuestion(q2);
        CheckIn submitted = CheckIn.builder().id(3L).patient(patient).submittedAt(OffsetDateTime.now()).build();
        when(checkInRepository.findById(3L)).thenReturn(Optional.of(submitted));
        when(checkInRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(checkInQuestionRepository.findByCheckIn_IdOrderByOrdinalAsc(3L)).thenReturn(List.of(s1, s2));
        when(answerRepository.findByCheckIn_Id(3L)).thenReturn(List.of(
                Answer.builder().question(q1).valueText("fine").build()));

        CheckInDetailDTO detail = service.markCheckInReviewed(3L, User.builder().role(Role.CAREGIVER).build());
        assertThat(detail).isNotNull();
        assertThat(service.markCheckInReviewed(3L, User.builder().role(Role.ADMIN).build())).isNotNull();

        assertThatThrownBy(() -> service.markCheckInReviewed(3L, null)).isInstanceOf(AppException.class);
        assertThatThrownBy(() -> service.markCheckInReviewed(3L, User.builder().role(Role.PATIENT).build()))
                .isInstanceOf(AppException.class);
        CheckIn draft = CheckIn.builder().id(4L).patient(patient).build();
        when(checkInRepository.findById(4L)).thenReturn(Optional.of(draft));
        assertThatThrownBy(() -> service.markCheckInReviewed(4L, User.builder().role(Role.ADMIN).build()))
                .isInstanceOf(AppException.class);
        assertThat(service.getCheckInDetail(4L)).isNotNull();
        when(checkInRepository.findById(anyLong())).thenReturn(Optional.empty());
        assertThatThrownBy(() -> service.getCheckInDetail(99L)).isInstanceOf(AppException.class);
    }
}
