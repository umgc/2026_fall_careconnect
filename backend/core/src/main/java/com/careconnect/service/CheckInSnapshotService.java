package com.careconnect.service;

import com.careconnect.dto.CheckInCreateRequestDTO;
import com.careconnect.dto.CheckInCreateResponseDTO;
import com.careconnect.dto.CheckInDetailDTO;
import com.careconnect.dto.CheckInAnswerDetailDTO;
import com.careconnect.dto.CheckInPageDTO;
import com.careconnect.dto.CheckInSummaryDTO;
import com.careconnect.dto.QuestionDTO;
import com.careconnect.exception.AppException;
import com.careconnect.model.Answer;
import com.careconnect.model.CheckIn;
import com.careconnect.model.CheckInQuestion;
import com.careconnect.model.Patient;
import com.careconnect.model.Question;
import com.careconnect.model.User;
import com.careconnect.repository.CheckInQuestionRepository;
import com.careconnect.repository.CheckInRepository;
import com.careconnect.repository.AnswerRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.QuestionRepository;
import com.careconnect.security.Role;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
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
    private final AnswerRepository answerRepository;
    private final PatientRepository patientRepository;
    private final QuestionRepository questionRepository;

    public CheckInSnapshotService(
            CheckInRepository checkInRepository,
            CheckInQuestionRepository checkInQuestionRepository,
            AnswerRepository answerRepository,
            PatientRepository patientRepository,
            QuestionRepository questionRepository
    ) {
        this.checkInRepository = checkInRepository;
        this.checkInQuestionRepository = checkInQuestionRepository;
        this.answerRepository = answerRepository;
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
    public CheckInPageDTO listCheckInsForPatientFiltered(
            Long patientId,
            String status,
            LocalDate startDate,
            LocalDate endDate,
            Integer page,
            Integer size
    ) {
        if (!patientRepository.existsById(patientId)) {
            throw new AppException(HttpStatus.NOT_FOUND, "Patient not found: " + patientId);
        }

        final int safePage = page == null || page < 0 ? 0 : page;
        final int safeSize = size == null || size <= 0 ? 20 : Math.min(size, 100);
        final String normalizedStatus = normalizeStatus(status);

        final OffsetDateTime rangeStart = startDate == null
                ? OffsetDateTime.MIN
                : startDate.atStartOfDay().atOffset(OffsetDateTime.now().getOffset());
        final OffsetDateTime rangeEnd = endDate == null
                ? OffsetDateTime.MAX
                : endDate.plusDays(1).atStartOfDay().atOffset(OffsetDateTime.now().getOffset()).minusNanos(1);
        if (rangeStart.isAfter(rangeEnd)) {
            throw new AppException(HttpStatus.BAD_REQUEST, "startDate must be on or before endDate");
        }

        List<CheckIn> all = checkInRepository.findByPatientIdOrderByCreatedAtDesc(patientId);
        List<CheckIn> filtered = all.stream()
                .filter(checkIn -> !checkIn.getCreatedAt().isBefore(rangeStart) && !checkIn.getCreatedAt().isAfter(rangeEnd))
                .filter(checkIn -> matchesStatus(checkIn, normalizedStatus))
                .sorted(Comparator.comparing(CheckIn::getCreatedAt).reversed())
                .toList();

        int totalElements = filtered.size();
        int totalPages = totalElements == 0 ? 0 : (int) Math.ceil((double) totalElements / safeSize);
        int fromIndex = Math.min(safePage * safeSize, totalElements);
        int toIndex = Math.min(fromIndex + safeSize, totalElements);
        List<CheckIn> pageItems = filtered.subList(fromIndex, toIndex);

        Map<Long, Integer> questionCounts = buildQuestionCountsMap(pageItems);
        List<CheckInSummaryDTO> items = pageItems.stream()
                .map(checkIn -> toSummary(checkIn, questionCounts))
                .toList();

        return new CheckInPageDTO(items, safePage, safeSize, totalElements, totalPages);
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

    public CheckInDetailDTO getCheckInDetail(Long checkInId, User currentUser) {
        CheckIn checkIn = checkInRepository.findById(checkInId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Check-in not found: " + checkInId));

        if (shouldMarkReviewed(checkIn, currentUser)) {
            checkIn.setReviewedAt(OffsetDateTime.now());
            checkIn = checkInRepository.save(checkIn);
        }

        List<CheckInQuestion> snapshotQuestions = checkInQuestionRepository.findByCheckIn_IdOrderByOrdinalAsc(checkInId);
        Map<Long, Answer> answersByQuestionId = new HashMap<>();
        for (Answer answer : answerRepository.findByCheckIn_Id(checkInId)) {
            answersByQuestionId.put(answer.getQuestion().getId(), answer);
        }

        List<CheckInAnswerDetailDTO> details = snapshotQuestions.stream()
                .map(snapshot -> {
                    Answer answer = answersByQuestionId.get(snapshot.getQuestion().getId());
                    return new CheckInAnswerDetailDTO(
                            snapshot.getQuestion().getId(),
                            snapshot.getPromptSnapshot(),
                            snapshot.getTypeSnapshot(),
                            snapshot.isRequired(),
                            snapshot.getOrdinal(),
                            answer == null ? null : answer.getValueText(),
                            answer == null ? null : answer.getValueBoolean(),
                            answer == null ? null : answer.getValueNumber(),
                            answer == null ? null : answer.getCreatedAt()
                    );
                })
                .toList();

        return new CheckInDetailDTO(
                checkIn.getId(),
                checkIn.getPatient().getId(),
                checkIn.getCreatedAt(),
                checkIn.getSubmittedAt(),
                checkIn.getReviewedAt(),
                computeStatus(checkIn),
                details
        );
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
                checkIn.getReviewedAt(),
                questionCounts.getOrDefault(checkIn.getId(), 0)
        );
    }

    private String normalizeStatus(String rawStatus) {
        if (rawStatus == null || rawStatus.isBlank()) {
            return null;
        }
        String normalized = rawStatus.trim().toLowerCase();
        if (!normalized.equals("draft") && !normalized.equals("submitted") && !normalized.equals("reviewed")) {
            throw new AppException(HttpStatus.BAD_REQUEST, "status must be one of: draft, submitted, reviewed");
        }
        return normalized;
    }

    private boolean matchesStatus(CheckIn checkIn, String status) {
        if (status == null) {
            return true;
        }
        return switch (status) {
            case "draft" -> checkIn.getSubmittedAt() == null;
            case "submitted" -> checkIn.getSubmittedAt() != null && checkIn.getReviewedAt() == null;
            case "reviewed" -> checkIn.getReviewedAt() != null;
            default -> true;
        };
    }

    private String computeStatus(CheckIn checkIn) {
        if (checkIn.getReviewedAt() != null) {
            return "reviewed";
        }
        if (checkIn.getSubmittedAt() != null) {
            return "submitted";
        }
        return "draft";
    }

    private boolean shouldMarkReviewed(CheckIn checkIn, User currentUser) {
        if (checkIn.getSubmittedAt() == null || checkIn.getReviewedAt() != null || currentUser == null || currentUser.getRole() == null) {
            return false;
        }
        Role role = currentUser.getRole();
        return role == Role.ADMIN || role == Role.CAREGIVER;
    }
}
