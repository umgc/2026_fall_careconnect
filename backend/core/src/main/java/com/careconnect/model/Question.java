// com.careconnect.model.Question
package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;
import java.util.Set;

@Entity
@Table(name = "questions")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Question {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, columnDefinition = "text")
    private String prompt;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 32)
    private QuestionType type;  // TEXT | YES_NO | TRUE_FALSE | NUMBER

    @Column(nullable = false)
    @Builder.Default
    private boolean required = false;

    @Column(nullable = false)
    @Builder.Default
    private boolean active = true;

    @Column(nullable = false)
    @Builder.Default
    private int ordinal = 0;

    @Column(name = "form_key", nullable = false, length = 64)
    @Builder.Default
    private String formKey = "virtual-checkin";

    @Column(name = "form_version", nullable = false)
    @Builder.Default
    private int formVersion = 1;

    @Column(name = "section_key", nullable = false, length = 64)
    @Builder.Default
    private String sectionKey = "general";

    @Column(name = "field_key", nullable = false, length = 128)
    @Builder.Default
    private String fieldKey = "question_field";

    @Column(name = "score_weight", precision = 8, scale = 2)
    private java.math.BigDecimal scoreWeight;

    @OneToMany(mappedBy = "question", cascade = CascadeType.ALL, orphanRemoval = true)
    private Set<CheckInQuestion> usedInCheckIns;
}
