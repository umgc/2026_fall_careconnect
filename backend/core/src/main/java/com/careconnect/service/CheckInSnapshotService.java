package com.careconnect.service;

import com.careconnect.dto.CheckInCreateRequestDTO;
import com.careconnect.dto.CheckInCreateResponseDTO;
import com.careconnect.dto.CheckInSummaryDTO;
import com.careconnect.dto.QuestionDTO;
import com.careconnect.exception.AppException;
import com.careconnect.model.CheckIn;
import com.careconnect.model.CheckInQuestion;
import com.careconnect.model.Patient;
import com.careconnect.model.Question;
import com.careconnect.repository.CheckInQuestionRepository;
import com.careconnect.repository.CheckInRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.QuestionRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
@Transactional
public class CheckInSnapshotService {

    private final CheckInRepository checkInRepository;
    private final CheckInQuestionRepository checkInQuestionRepository;
    private final PatientRepository patientRepository;
    private final QuestionRepository questionRepository;

    public CheckInSnapshotService(
            CheckInRepository checkInRepository,
            CheckInQuestionRepository checkInQuestionRepository,
            PatientRepository patientRepository,
            QuestionRepository questionRepository
    ) {
        this.checkInRepository = checkInRepository;
        this.checkInQuestionRepository = checkInQuestionRepository;
        this.patientRepository = patientRepository;
        this.questionRepository = questionRepository;
    }

    public CheckInCreateResponseDTO createCheckInWithSnapshot(CheckInCreateRequestDTO request) {
        Patient patient = patientRepository.findById(request.patientId())
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found: " + request.patientId()));

        Set<Long> dedupedIds = new LinkedHashSet<>(request.selectedQuestionIds());
        List<Question> questions = questionRepository.findAllById(dedupedIds);
        if (questions.size() != dedupedIds.size()) {
            Set<Long> found = questions.stream().map(Question::getId).collect(Collectors.toSet());
            List<Long> missing = dedupedIds.stream().filter(id -> !found.contains(id)).toList();
            throw new AppException(HttpStatus.BAD_REQUEST, "Unknown question ids: " + missing);
        }

        List<Long> inactiveIds = questions.stream()
                .filter(q -> !q.isActive())
                .map(Question::getId)
                .toList();
        if (!inactiveIds.isEmpty()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Cannot assign inactive questions: " + inactiveIds);
        }

        CheckIn checkIn = CheckIn.builder()
                .patient(patient)
                .build();
        checkIn = checkInRepository.save(checkIn);

        Map<Long, Question> byId = questions.stream()
                .collect(Collectors.toMap(Question::getId, Function.identity()));
        List<CheckInQuestion> snapshots = new ArrayList<>();
        for (Long questionId : dedupedIds) {
            Question q = byId.get(questionId);
            snapshots.add(new CheckInQuestion(
                    checkIn,
                    q,
                    q.isRequired(),
                    q.getOrdinal(),
                    q.getPrompt(),
                    q.getType().name()
            ));
        }
        checkInQuestionRepository.saveAll(snapshots);

        return new CheckInCreateResponseDTO(
                checkIn.getId(),
                patient.getId(),
                checkIn.getCreatedAt(),
                snapshots.size()
        );
    }

    @Transactional(readOnly = true)
    public List<QuestionDTO> getSnapshotQuestions(Long checkInId) {
        List<QuestionDTO> questions = checkInQuestionRepository.findSnapshotQuestionDtosByCheckInId(checkInId);
        if (questions.isEmpty() && !checkInRepository.existsById(checkInId)) {
            throw new AppException(HttpStatus.NOT_FOUND, "Check-in not found: " + checkInId);
        }
        return questions;
    }

    @Transactional(readOnly = true)
    public Long getPatientIdForCheckIn(Long checkInId) {
        return checkInRepository.findById(checkInId)
                .map(checkIn -> checkIn.getPatient().getId())
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Check-in not found: " + checkInId));
    }

    @Transactional(readOnly = true)
    public List<CheckInSummaryDTO> listCheckInsForPatient(Long patientId) {
        if (!patientRepository.existsById(patientId)) {
            throw new AppException(HttpStatus.NOT_FOUND, "Patient not found: " + patientId);
        }
        List<CheckIn> checkIns = checkInRepository.findByPatientIdOrderByCreatedAtDesc(patientId);
        Map<Long, Integer> questionCounts = buildQuestionCountsMap(checkIns);
        return checkIns.stream()
                .map(checkIn -> toSummary(checkIn, questionCounts))
                .toList();
    }

    @Transactional(readOnly = true)
    public Optional<CheckInSummaryDTO> getLatestCheckInForPatient(Long patientId) {
        if (!patientRepository.existsById(patientId)) {
            throw new AppException(HttpStatus.NOT_FOUND, "Patient not found: " + patientId);
        }
        return checkInRepository.findTopByPatientIdOrderByCreatedAtDesc(patientId)
                .map(checkIn -> {
                    Map<Long, Integer> counts = buildQuestionCountsMap(List.of(checkIn));
                    return toSummary(checkIn, counts);
                });
    }

    private Map<Long, Integer> buildQuestionCountsMap(List<CheckIn> checkIns) {
        if (checkIns.isEmpty()) {
            return Map.of();
        }
        Set<Long> checkInIds = checkIns.stream().map(CheckIn::getId).collect(Collectors.toSet());
        return checkInQuestionRepository.countByCheckInIds(checkInIds).stream()
                .collect(Collectors.toMap(
                        CheckInQuestionRepository.CheckInQuestionCountProjection::getCheckInId,
                        count -> Math.toIntExact(count.getQuestionCount())
                ));
    }

    private CheckInSummaryDTO toSummary(CheckIn checkIn, Map<Long, Integer> questionCounts) {
        return new CheckInSummaryDTO(
                checkIn.getId(),
                checkIn.getPatient().getId(),
                checkIn.getCreatedAt(),
                checkIn.getSubmittedAt(),
                questionCounts.getOrDefault(checkIn.getId(), 0)
        );
    }
}
