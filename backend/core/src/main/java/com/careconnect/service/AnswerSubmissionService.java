package com.careconnect.service;

import com.careconnect.dto.AnswerUpsertRequestDTO;
import com.careconnect.dto.SubmitAnswersRequestDTO;
import com.careconnect.dto.SubmitAnswersResponseDTO;
import com.careconnect.exception.AppException;
import com.careconnect.model.Answer;
import com.careconnect.model.CheckIn;
import com.careconnect.model.CheckInQuestion;
import com.careconnect.repository.AnswerRepository;
import com.careconnect.repository.CheckInQuestionRepository;
import com.careconnect.repository.CheckInRepository;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

@Service
@Transactional
public class AnswerSubmissionService {

    private final CheckInRepository checkInRepository;
    private final CheckInQuestionRepository checkInQuestionRepository;
    private final AnswerRepository answerRepository;

    public AnswerSubmissionService(
            CheckInRepository checkInRepository,
            CheckInQuestionRepository checkInQuestionRepository,
            AnswerRepository answerRepository
    ) {
        this.checkInRepository = checkInRepository;
        this.checkInQuestionRepository = checkInQuestionRepository;
        this.answerRepository = answerRepository;
    }

    public SubmitAnswersResponseDTO submitAnswers(Long checkInId, SubmitAnswersRequestDTO request) {
        CheckIn checkIn = checkInRepository.findById(checkInId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Check-in not found: " + checkInId));

        // Guard against re-submission
        if (checkIn.getSubmittedAt() != null) {
            throw new AppException(HttpStatus.CONFLICT, "Check-in already submitted");
        }

        List<CheckInQuestion> selectedQuestions = checkInQuestionRepository.findByCheckIn_IdOrderByOrdinalAsc(checkInId);
        if (selectedQuestions.isEmpty()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "No assigned questions for check-in: " + checkInId);
        }

        Map<Long, CheckInQuestion> snapshotByQuestionId = new HashMap<>();
        Set<Long> requiredQuestionIds = new HashSet<>();
        for (CheckInQuestion ciq : selectedQuestions) {
            Long questionId = ciq.getQuestion().getId();
            snapshotByQuestionId.put(questionId, ciq);
            if (ciq.isRequired()) {
                requiredQuestionIds.add(questionId);
            }
        }

        // Fetch all existing answers for this check-in to avoid N+1 queries
        List<Answer> existingAnswers = answerRepository.findByCheckIn_Id(checkInId);
        Set<Long> existingAnswerQuestionIds = new HashSet<>();
        for (Answer answer : existingAnswers) {
            existingAnswerQuestionIds.add(answer.getQuestion().getId());
        }

        Set<Long> answeredQuestionIds = new HashSet<>();
        List<Answer> toPersist = new ArrayList<>();
        for (AnswerUpsertRequestDTO item : request.answers()) {
            if (item.questionId() == null) {
                throw new AppException(HttpStatus.BAD_REQUEST, "questionId must not be null");
            }
            if (!answeredQuestionIds.add(item.questionId())) {
                throw new AppException(HttpStatus.BAD_REQUEST, "Duplicate questionId in request: " + item.questionId());
            }

            CheckInQuestion snapshot = snapshotByQuestionId.get(item.questionId());
            if (snapshot == null) {
                throw new AppException(HttpStatus.BAD_REQUEST, "Question is not assigned to this check-in: " + item.questionId());
            }

            if (existingAnswerQuestionIds.contains(item.questionId())) {
                throw new AppException(HttpStatus.CONFLICT, "Answer already exists for question: " + item.questionId());
            }

            validateTypedValue(snapshot.getTypeSnapshot(), item);

            Answer answer = Answer.builder()
                    .checkIn(checkIn)
                    .question(snapshot.getQuestion())
                    .valueText(item.valueText())
                    .valueBoolean(item.valueBoolean())
                    .valueNumber(item.valueNumber())
                    .build();
            toPersist.add(answer);
        }

        Set<Long> missingRequired = new HashSet<>(requiredQuestionIds);
        missingRequired.removeAll(answeredQuestionIds);
        if (!missingRequired.isEmpty()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Missing required answers for questionIds: " + missingRequired);
        }

        try {
            answerRepository.saveAll(toPersist);
            checkIn.setSubmittedAt(OffsetDateTime.now());
            checkInRepository.save(checkIn);
        } catch (DataIntegrityViolationException e) {
            // Race condition: another request already submitted this check-in or created conflicting answers
            throw new AppException(HttpStatus.CONFLICT, "Check-in submission conflict (possible duplicate submission)");
        }

        return new SubmitAnswersResponseDTO(checkInId, toPersist.size(), checkIn.getSubmittedAt());
    }

    private void validateTypedValue(String questionType, AnswerUpsertRequestDTO item) {
        int populated = (item.valueText() != null ? 1 : 0)
                + (item.valueBoolean() != null ? 1 : 0)
                + (item.valueNumber() != null ? 1 : 0);
        if (populated != 1) {
            throw new AppException(
                    HttpStatus.BAD_REQUEST,
                    "Exactly one of valueText/valueBoolean/valueNumber must be set for questionId: " + item.questionId()
            );
        }

        switch (questionType) {
            case "TEXT" -> {
                if (item.valueText() == null || item.valueText().trim().isEmpty()) {
                    throw new AppException(HttpStatus.BAD_REQUEST, "TEXT question requires non-empty valueText: " + item.questionId());
                }
            }
            case "YES_NO", "TRUE_FALSE" -> {
                if (item.valueBoolean() == null) {
                    throw new AppException(HttpStatus.BAD_REQUEST, questionType + " question requires valueBoolean: " + item.questionId());
                }
            }
            case "NUMBER" -> {
                if (item.valueNumber() == null) {
                    throw new AppException(HttpStatus.BAD_REQUEST, "NUMBER question requires valueNumber: " + item.questionId());
                }
            }
            default -> throw new AppException(HttpStatus.BAD_REQUEST, "Unsupported question type in snapshot: " + questionType);
        }
    }
}
