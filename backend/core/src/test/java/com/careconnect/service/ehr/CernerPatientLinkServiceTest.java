package com.careconnect.service.ehr;

import com.careconnect.config.CernerProperties;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class CernerPatientLinkServiceTest {

    @Mock private PatientRepository patients;
    @Mock private EhrSourceRepository sources;
    @Mock private EhrPatientCrosswalkRepository crosswalks;

    private CernerPatientLinkService service;

    @BeforeEach
    void setUp() {
        service = new CernerPatientLinkService(patients, sources, crosswalks);
    }

    @Test
    void storesNormalizedSmartPatientAgainstOracleHealthSource() {
        Patient patient = Patient.builder().id(42L).build();
        EhrSource source = EhrSource.builder().id(5L)
                .code(CernerProperties.SOURCE_ORACLE_HEALTH).build();
        when(patients.findByUserId(7L)).thenReturn(Optional.of(patient));
        when(sources.findByCode(CernerProperties.SOURCE_ORACLE_HEALTH))
                .thenReturn(Optional.of(source));
        when(crosswalks.findBySourceIdAndExternalPatientId(5L, "12724066"))
                .thenReturn(Optional.empty());
        when(crosswalks.findByPatientIdAndSourceId(42L, 5L)).thenReturn(Optional.empty());
        when(crosswalks.save(any(EhrPatientCrosswalk.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        EhrPatientCrosswalk linked = service.link(7L, "Patient/12724066");

        assertThat(linked.getPatientId()).isEqualTo(42L);
        assertThat(linked.getSourceId()).isEqualTo(5L);
        assertThat(linked.getExternalPatientId()).isEqualTo("12724066");
    }

    @Test
    void rejectsExternalPatientAlreadyOwnedByAnotherLocalPatient() {
        Patient patient = Patient.builder().id(42L).build();
        EhrSource source = EhrSource.builder().id(5L).build();
        EhrPatientCrosswalk existing = EhrPatientCrosswalk.builder()
                .patientId(99L).sourceId(5L).externalPatientId("12724066").build();
        when(patients.findByUserId(7L)).thenReturn(Optional.of(patient));
        when(sources.findByCode(CernerProperties.SOURCE_ORACLE_HEALTH))
                .thenReturn(Optional.of(source));
        when(crosswalks.findBySourceIdAndExternalPatientId(5L, "12724066"))
                .thenReturn(Optional.of(existing));

        assertThatThrownBy(() -> service.link(7L, "12724066"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("another patient");
        verify(crosswalks, never()).save(any());
    }
}
