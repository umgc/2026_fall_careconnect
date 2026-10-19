// com.careconnect.model.CheckIn
package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;

import java.time.OffsetDateTime;
import java.util.*;

@Entity
@Table(
        name = "check_ins",
        indexes = {
                // Note: JPA's @Index doesn't support "DESC" in columnList; just list columns.
                @Index(name = "idx_checkins_patient_created", columnList = "patient_id, created_at")
        }
)
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class CheckIn {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // FK -> patients(id)
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "patient_id", nullable = false)
    private Patient patient;

    @Column(name = "created_at", nullable = false)
    @Builder.Default
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "submitted_at")
    private OffsetDateTime submittedAt;

    @Column(name = "reviewed_at")
    private OffsetDateTime reviewedAt;

    // Existing relation to answers
    @OneToMany(mappedBy = "checkIn", cascade = CascadeType.ALL, orphanRemoval = true)
    @Builder.Default
    private List<Answer> answers = new ArrayList<>();

    // NEW: snapshot of caregiver-selected questions for this check-in
    @OneToMany(mappedBy = "checkIn", cascade = CascadeType.ALL, orphanRemoval = true)
    @Builder.Default
    private Set<CheckInQuestion> selectedQuestions = new HashSet<>();

    // (Optional) helper methods keep both sides in sync
    public void addSelectedQuestion(CheckInQuestion cq) {
        cq.setCheckIn(this);
        selectedQuestions.add(cq);
    }

    public void removeSelectedQuestion(CheckInQuestion cq) {
        selectedQuestions.remove(cq);
        cq.setCheckIn(null);
    }
}
