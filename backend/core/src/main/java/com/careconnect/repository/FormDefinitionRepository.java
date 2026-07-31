package com.careconnect.repository;

import com.careconnect.model.forms.FormDefinition;
import com.careconnect.model.forms.FormType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

@Repository
public interface FormDefinitionRepository extends JpaRepository<FormDefinition, Long> {

    Optional<FormDefinition> findByFormTypeAndVersion(FormType formType, String version);

    List<FormDefinition> findByFormType(FormType formType);

    Optional<FormDefinition> findFirstByFormTypeAndStatus(FormType formType, FormDefinition.FormStatus status);

    List<FormDefinition> findByStatus(FormDefinition.FormStatus status);

    /**
     * Resolve the version that is in effect for a form type on a given date:
     * the latest-effective ACTIVE definition whose window contains {@code on}.
     */
    default Optional<FormDefinition> findEffective(FormType formType, LocalDate on) {
        return findByFormType(formType).stream()
                .filter(d -> d.getStatus() == FormDefinition.FormStatus.ACTIVE)
                .filter(d -> !d.getEffectiveDate().isAfter(on))
                .filter(d -> d.getExpirationDate() == null || !d.getExpirationDate().isBefore(on))
                .max((a, b) -> a.getEffectiveDate().compareTo(b.getEffectiveDate()));
    }
}
