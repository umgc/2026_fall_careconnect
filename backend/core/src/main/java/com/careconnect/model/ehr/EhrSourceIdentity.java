package com.careconnect.model.ehr;

import com.careconnect.model.Auditable;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hl7.fhir.r4.model.ContactPoint;
import org.hl7.fhir.r4.model.Patient;

import java.time.Instant;
import java.time.LocalDate;

/**
 * What one external source currently believes about a patient's identity — the demographic
 * snapshot reconciliation compares against the canonical {@code patient} record.
 * <p>
 * One row per (patient, source), upserted on each sync rather than appended. That shape is
 * required, not stylistic: {@code RecencyWinsIdentityReconciler} diffs this against
 * {@code patient} field by field under a row lock, and an append-only history has no stable
 * row to lock.
 * <p>
 * {@code sourceUpdatedAt} is an {@link Instant} deliberately. It is the field every recency
 * comparison runs on, and it is compared <em>across</em> sources; a zone-less type would let a
 * snapshot from a source in another offset appear newer than it is and win when it should
 * lose.
 * <p>
 * Carries no organization column — see the 2026-09-26 org-scoping reversal. Stores bare
 * {@code patientId}/{@code sourceId} rather than {@code @ManyToOne}, matching the rest of this
 * package; the foreign keys are applied by {@code SchemaPatchRunner}.
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(
        name = "ehr_source_identity",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_ehr_source_identity_patient_source",
                columnNames = {"patient_id", "source_id"}),
        indexes = @Index(
                name = "idx_ehr_source_identity_patient",
                columnList = "patient_id"))
public class EhrSourceIdentity extends Auditable {

    public EhrSourceIdentity(Long patientId, Patient patient, Long sourceId){
        this.patientId = patientId;
        this.sourceId = sourceId;
        this.sourceUpdatedAt = patient.getMeta().getLastUpdated().toInstant();
        this.givenName = patient.getNameFirstRep().getGivenAsSingleString();
        this.familyName = patient.getNameFirstRep().getFamily();

        this.gender = patient.getGender().getDisplay();
        // Wow this is a stupid conversion method.
        this.dateOfBirth = LocalDate.from(patient.getBirthDate().toInstant());


        for(ContactPoint point: patient.getTelecom()){
            if(point.getSystem().equals(ContactPoint.ContactPointSystem.PHONE)){
                this.phone = point.getValue();
            }else{
                if(point.getSystem().equals(ContactPoint.ContactPointSystem.EMAIL)){
                    this.email = point.getValue();
                }
            }
        }

        this.managingOrg = patient.getManagingOrganization().getDisplay();
        this.language = patient.getCommunicationFirstRep().getLanguage().getText();
        this.memberId = patient.getIdentifierFirstRep().getValue();
        this.addressLine1 = patient.getAddressFirstRep().getLine().get(0).getValue();
        this.addressLine2 = patient.getAddressFirstRep().getLine().get(1).getValue();
        this.city = patient.getAddressFirstRep().getCity();
        this.state = patient.getAddressFirstRep().getState();
        this.postalCode = patient.getAddressFirstRep().getPostalCode();
    }


    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    /** References {@code ehr_source.id}. */
    @Column(name = "source_id", nullable = false)
    private Long sourceId;

    /**
     * The source's own last-modified time for this identity, normally FHIR
     * {@code meta.lastUpdated}. Never the time we fetched it — recency means the source's
     * recency, not ours.
     */
    @Column(name = "source_updated_at", nullable = false)
    private Instant sourceUpdatedAt;

    @Column(name = "given_name", length = 100)
    private String givenName;

    @Column(name = "family_name", length = 100)
    private String familyName;

    /**
     * Held as a real date, unlike {@code patient.dob} which is currently a String. The
     * reconciliation library compares field values as strings, so an adapter converts at the
     * boundary; storing a date as text here would lose that validation for no benefit. The
     * inconsistency with {@code patient.dob} is pre-existing and worth correcting separately.
     */
    @Column(name = "date_of_birth")
    private LocalDate dateOfBirth;

    @Column(name = "phone", length = 32)
    private String phone;

    @Column(name = "email", length = 254)
    private String email;

    @Column(name = "address_line1", length = 255)
    private String addressLine1;

    @Column(name = "address_line2", length = 255)
    private String addressLine2;

    @Column(name = "city", length = 100)
    private String city;

    @Column(name = "state", length = 50)
    private String state;

    @Column(name = "postal_code", length = 20)
    private String postalCode;

    // ---- Carried but not reconciled (added 2026-09-29) ----
    //
    // These four were identified early as fields real sources supply, then deferred so Phase 2 could
    // ship. Deferring them twice is how a field quietly stops existing, so they are captured here
    // now: a connector that has the value can store it, and nothing has to be re-derived from
    // ehr_raw_payload later.
    //
    // None of them is in the reconciliation vocabulary, and adding a column here does not put it
    // there -- that list lives in JpaPatientFieldAccessor and is bounded by what `patient` can
    // actually hold. Three of these have no counterpart on `patient` at all. The fourth, gender,
    // does, and is deliberately still excluded; see its note below.

    /**
     * The subscriber or member identifier this source knows the patient by — FHIR
     * {@code Coverage.subscriberId}, or the equivalent member number on an insurer's own API.
     * <p>
     * Not {@code patient.ma_number}: that is a Medical Assistance number for EVV compliance, issued
     * by the state, and it is not the same identifier even when a source happens to return one that
     * looks similar. Kept distinct so nobody reconciles one onto the other.
     */
    @Column(name = "member_id", length = 128)
    private String memberId;

    /**
     * The source's administrative gender, stored verbatim as the source stated it — FHIR
     * {@code Patient.gender}, whose value set is {@code male | female | other | unknown}.
     * <p>
     * <b>Deliberately not reconciled onto {@code patient.gender}.</b> Our {@code Gender} enum is
     * {@code MALE, FEMALE, OTHER, PREFER_NOT_TO_SAY}, and the mismatch is not cosmetic: FHIR's
     * {@code unknown} means <em>this system does not know</em>, while {@code PREFER_NOT_TO_SAY}
     * means <em>the patient was asked and declined</em>. Mapping one to the other would record a
     * statement the patient never made, on a field people are entitled to have recorded correctly.
     * <p>
     * So the source's answer is kept here, unmapped, until someone decides what the two vocabularies
     * should mean to each other. Storing it costs nothing and keeps the option open; guessing the
     * mapping would close it silently.
     */
    @Column(name = "gender", length = 16)
    private String gender;

    /**
     * The organization the source says is responsible for this patient's record — FHIR
     * {@code Patient.managingOrganization}, stored as its display name rather than a reference,
     * since we hold no organization table to point at.
     * <p>
     * Worth noting for FR-EHR-10: this is the closest thing to an org affiliation anywhere in the
     * schema. It is a <em>source's claim about itself</em>, not a tenancy boundary, and must not be
     * pressed into service as one — but if a tenancy model is ever built, this is real data about
     * what the sources were already telling us.
     */
    @Column(name = "managing_org", length = 255)
    private String managingOrg;

    /**
     * The patient's preferred language as the source reports it — FHIR
     * {@code Patient.communication[].language}, a BCP-47 tag such as {@code en-US}.
     * <p>
     * Only the first/preferred entry is carried. A patient may have several, and if that turns out
     * to matter it wants its own table rather than a delimited column here.
     */
    @Column(name = "language", length = 35)
    private String language;
}
