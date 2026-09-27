package com.careconnect.model.ehr;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.JdbcType;

import java.time.OffsetDateTime;
import java.util.Map;

@Builder
@Entity
@Table(name = "ehr_audit_events")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class EhrAuditEvent {

    @Getter
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    long id;

    @Getter
    long patientId;

    @Getter
    String source;

    @Getter
    String resourceType;

    @Getter
    EhrRetrievalOutcome outcome;

    @Getter
    long actorUserId;

    @Getter
    int recordCount;


    @Getter
    OffsetDateTime eventTime;

    public void onCreate(){}
}
