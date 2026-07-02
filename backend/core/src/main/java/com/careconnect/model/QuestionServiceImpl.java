package com.careconnect.model;

import com.careconnect.dto.QuestionDTO;
import com.careconnect.dto.QuestionMapper;
import com.careconnect.dto.QuestionUpsertDTO;
import com.careconnect.repository.QuestionRepository;
import com.careconnect.service.QuestionService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

@Service
@Transactional
public class QuestionServiceImpl implements QuestionService {

    private final QuestionRepository repo;

    public QuestionServiceImpl(QuestionRepository repo) {
        this.repo = repo;
    }

    @Override
    @Transactional(readOnly = true)
    public List<QuestionDTO> listQuestions(Boolean active) {
        List<Question> src;
        if (active == null) {
            // all questions ordered by ordinal
            src = repo.findAllByOrderByOrdinalAsc();
        } else if (active) {
            // only active, ordered
            src = repo.findAllByActiveTrueOrderByOrdinalAsc();
        } else {
            // only inactive, ordered
            src = repo.findAllByActiveFalseOrderByOrdinalAsc();
        }
        return src.stream().map(QuestionMapper::toDto).toList();
    }

    // #3: used by /v1/api/checkins/{id}/questions
    @Override
    @Transactional(readOnly = true)
    public List<QuestionDTO> findActiveOrdered() {
        return repo.findAllByActiveTrueOrderByOrdinalAsc()
                .stream()
                .map(QuestionMapper::toDto)
                .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<QuestionDTO> getOne(Long id) {
        return repo.findById(id).map(QuestionMapper::toDto);
    }

    @Override
    public QuestionDTO create(QuestionUpsertDTO body) {
        Question q = new Question();
        QuestionMapper.applyUpsert(q, body);
        q.setActive(true);
        // Shift existing questions at or above the target ordinal to avoid conflicts.
        // Use Long.MAX_VALUE as the exclude-id sentinel since q has no id yet.
        resolveOrdinalConflict(q.getOrdinal(), Long.MAX_VALUE);
        q = repo.save(q);
        return QuestionMapper.toDto(q);
    }

    @Override
    public Optional<QuestionDTO> update(Long id, QuestionUpsertDTO body) {
        return repo.findById(id).map(existing -> {
            int newOrdinal = body.ordinal();
            // Only shift if ordinal is actually changing and the slot is already taken.
            if (newOrdinal != existing.getOrdinal() && repo.existsByOrdinalAndIdNot(newOrdinal, id)) {
                repo.shiftOrdinalsUp(newOrdinal, id);
            }
            QuestionMapper.applyUpsert(existing, body);
            existing = repo.save(existing);
            return QuestionMapper.toDto(existing);
        });
    }

    @Override
    public Optional<QuestionDTO> setActive(Long id, boolean active) {
        return repo.findById(id).map(existing -> {
            existing.setActive(active);
            existing = repo.save(existing);
            return QuestionMapper.toDto(existing);
        });
    }

    /**
     * Shifts all questions at or above {@code targetOrdinal} up by 1 when the slot is occupied.
     *
     * @param targetOrdinal the ordinal the caller wants to claim
     * @param excludeId     the id of the question being placed (Long.MAX_VALUE for new questions)
     */
    private void resolveOrdinalConflict(int targetOrdinal, Long excludeId) {
        if (repo.existsByOrdinalAndIdNot(targetOrdinal, excludeId)) {
            repo.shiftOrdinalsUp(targetOrdinal, excludeId);
        }
    }
}
