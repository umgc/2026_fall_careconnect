package com.careconnect.model;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;


// TODO

@Setter
@Getter
@Entity
@Table(name = "check_in_questions")
public class CheckInQuestion {

    @EmbeddedId
    private CheckInQuestionId id;

    @MapsId("checkInId")
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "check_in_id", nullable = false)
    private CheckIn checkIn;

    @MapsId("questionId")
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "question_id", nullable = false)
    private Question question;

    // Snapshot fields from the master question at selection time
    @Column(nullable = false)
    private boolean required;

    @Column(nullable = false)
    private int ordinal;

    @Column(name = "prompt_snapshot", nullable = false, columnDefinition = "text")
    private String promptSnapshot;

    @Column(name = "type_snapshot", nullable = false, length = 32)
    private String typeSnapshot;

    public CheckInQuestion() {}

    public CheckInQuestion(
            CheckIn checkIn,
            Question question,
            boolean required,
            int ordinal,
            String promptSnapshot,
            String typeSnapshot
    ) {
        this.checkIn = checkIn;
        this.question = question;
        this.required = required;
        this.ordinal = ordinal;
        this.promptSnapshot = promptSnapshot;
        this.typeSnapshot = typeSnapshot;
        this.id = new CheckInQuestionId(
            checkIn.getId(), 
            question.getId()
        );
    }

}
