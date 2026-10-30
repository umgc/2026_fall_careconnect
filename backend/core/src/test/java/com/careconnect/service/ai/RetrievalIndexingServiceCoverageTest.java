package com.careconnect.service.ai;

import com.careconnect.controller.RetrievalIndexingController;
import com.careconnect.model.Medication;
import com.careconnect.model.Task;
import com.careconnect.model.User;
import com.careconnect.model.Vital;
import com.careconnect.repository.MedicationRepository;
import com.careconnect.repository.TaskRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.VitalsRepository;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ai.retrieval.ForbiddenScopeException;
import com.careconnect.service.ai.retrieval.RetrievalScopeService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.when;

class RetrievalIndexingServiceCoverageTest {

    @AfterEach
    void clear() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void indexPatientWritesMedicationTaskAndVitalChunks() {
        RetrievalIndexChunkRepository chunks = mock(RetrievalIndexChunkRepository.class);
        MedicationRepository meds = mock(MedicationRepository.class);
        TaskRepository tasks = mock(TaskRepository.class);
        VitalsRepository vitals = mock(VitalsRepository.class);
        when(meds.findActiveByPatientId(1L)).thenReturn(List.of(
                Medication.builder().id(1L).medicationName("Aspirin").dosage("81mg").build()));
        when(tasks.findByPatientId(1L)).thenReturn(Optional.of(List.of(Task.builder().id(2L).name("Walk").build())));
        Vital full = Vital.builder().id(3L).vitalType("HEART_RATE").value("72").unit("bpm")
                .recordedAt(LocalDateTime.now()).notes("rest").isAbnormal(true).build();
        Vital bare = Vital.builder().id(4L).vitalType("TEMP").value("98").build();
        bare.setRecordedAt(null);
        when(vitals.findByPatientIdOrderByRecordedAtDesc(1L)).thenReturn(List.of(full, bare));
        RetrievalIndexingService service = new RetrievalIndexingService(chunks, meds, tasks, vitals);
        assertThat(service.indexPatient(1L)).isEqualTo(4);
    }

    @Test
    void controllerMapsScopeOutcomes() throws Exception {
        RetrievalIndexingService indexing = mock(RetrievalIndexingService.class);
        RetrievalScopeService scope = mock(RetrievalScopeService.class);
        UserRepository users = mock(UserRepository.class);
        User caller = User.builder().id(9L).email("a@example.test").role(Role.ADMIN).build();
        when(users.findByEmail("a@example.test")).thenReturn(Optional.of(caller));
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("a@example.test", null, List.of()));
        when(indexing.indexPatient(1L)).thenReturn(3);
        RetrievalIndexingController controller = new RetrievalIndexingController(indexing, scope, users);
        assertThat(controller.index(1L).getBody()).containsEntry("chunksIndexed", 3);

        doThrow(ForbiddenScopeException.unsupportedRole(Role.ADMIN, 9L, "no", null))
                .when(scope).resolveRetrievalScope(any(User.class), anyLong());
        assertThat(controller.index(1L).getStatusCode().value()).isEqualTo(403);
        reset(scope);
        doThrow(new UnauthorizedException("no")).when(scope).resolveRetrievalScope(any(User.class), anyLong());
        assertThat(controller.index(1L).getStatusCode().value()).isEqualTo(401);
    }
}
