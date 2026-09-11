package com.careconnect.model;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import org.hl7.fhir.r4.model.Patient;



@Entity
@Table(name = "ehr_identities")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
class EHRIdentity{


}