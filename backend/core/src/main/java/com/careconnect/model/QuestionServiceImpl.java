package com.careconnect.model;

import com.careconnect.dto.QuestionDTO;
import com.careconnect.dto.QuestionMapper;
import com.careconnect.dto.QuestionUpsertDTO;
import com.careconnect.repository.QuestionRepository;
import com.careconnect.service.QuestionService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.Locale;

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
        return listQuestions(active, null, null);
    }

    @Override
    @Transactional(readOnly = true)
    public List<QuestionDTO> listQuestions(Boolean active, String formKey, Integer formVersion) {
        return repo.findByFilters(active, normalizeKey(formKey), formVersion)
                .stream()
                .map(QuestionMapper::toDto)
                .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public List<QuestionDTO> findActiveOrdered() {
        return repo.findAllByActiveTrueAndFormKeyAndFormVersionOrderByOrdinalAsc(DEFAULT_FORM_KEY, DEFAULT_FORM_VERSION)
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
        applyMetadataDefaults(q, body);
        q.setActive(true);
        resolveOrdinalConflict(q.getOrdinal(), Long.MAX_VALUE, q.getFormKey(), q.getFormVersion());
        q = repo.save(q);
        return QuestionMapper.toDto(q);
    }

    @Override
    public Optional<QuestionDTO> update(Long id, QuestionUpsertDTO body) {
        return repo.findById(id).map(existing -> {
            int previousOrdinal = existing.getOrdinal();
            String previousFormKey = existing.getFormKey();
            int previousFormVersion = existing.getFormVersion();

            QuestionMapper.applyUpsert(existing, body);
            applyMetadataDefaults(existing, body);

            boolean ordinalChanged = existing.getOrdinal() != previousOrdinal;
            boolean formChanged = !Objects.equals(existing.getFormKey(), previousFormKey)
                    || existing.getFormVersion() != previousFormVersion;
            if (ordinalChanged || formChanged) {
                resolveOrdinalConflict(existing.getOrdinal(), id, existing.getFormKey(), existing.getFormVersion());
            }
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

    private void resolveOrdinalConflict(int targetOrdinal, Long excludeId, String formKey, int formVersion) {
        if (repo.existsByOrdinalAndFormKeyAndFormVersionAndIdNot(targetOrdinal, formKey, formVersion, excludeId)) {
            repo.shiftOrdinalsUp(targetOrdinal, excludeId, formKey, formVersion);
        }
    }

    private void applyMetadataDefaults(Question q, QuestionUpsertDTO body) {
        if (q.getFormKey() == null || q.getFormKey().isBlank()) {
            q.setFormKey(DEFAULT_FORM_KEY);
        } else {
            q.setFormKey(normalizeKey(q.getFormKey()));
        }

        if (q.getFormVersion() < 1) {
            q.setFormVersion(DEFAULT_FORM_VERSION);
        }

        if (q.getSectionKey() == null || q.getSectionKey().isBlank()) {
            q.setSectionKey(DEFAULT_SECTION_KEY);
        } else {
            q.setSectionKey(normalizeKey(q.getSectionKey()));
        }

        if (q.getFieldKey() == null || q.getFieldKey().isBlank()) {
            q.setFieldKey(generateFieldKey(body.prompt()));
        } else {
            q.setFieldKey(normalizeFieldKey(q.getFieldKey()));
        }

        if (body.scoreWeight() != null) {
            q.setScoreWeight(BigDecimal.valueOf(body.scoreWeight()));
        } else if (q.getScoreWeight() != null && q.getScoreWeight().compareTo(BigDecimal.ZERO) < 0) {
            q.setScoreWeight(BigDecimal.ZERO);
        }
    }

    private String generateFieldKey(String prompt) {
        String normalized = normalizeFieldKey(prompt);
        if (!normalized.isBlank()) {
            return normalized;
        }
        return "question_field";
    }

    private String normalizeKey(String value) {
        if (value == null) return null;
        String normalized = value.trim().toLowerCase(Locale.ROOT).replace(' ', '-');
        return normalized.isBlank() ? null : normalized;
    }

    private String normalizeFieldKey(String value) {
        if (value == null) return "";
        String normalized = value.trim().toLowerCase(Locale.ROOT)
                .replaceAll("[^a-z0-9]+", "_")
                .replaceAll("^_+|_+$", "")
                .replaceAll("_+", "_");
        if (normalized.length() > 128) {
            return normalized.substring(0, 128);
        }
        return normalized;
    }

    private static final String DEFAULT_FORM_KEY = "virtual-checkin";
    private static final int DEFAULT_FORM_VERSION = 1;
    private static final String DEFAULT_SECTION_KEY = "general";
}
