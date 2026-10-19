package com.careconnect.security;

import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.ConsentGrantRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * What a refusal from {@link MedicareAccessPolicy} looks like over HTTP, with the application's
 * real {@link GlobalExceptionHandler} in place (WBS 6.2.37; SRS FR-MCR-17, NFR-DEG-03).
 * <p>
 * No Medicare endpoint calls the guard yet, so a stand-in controller does exactly what the guard's
 * Javadoc asks the endpoints to do: load the caller from the request's principal with
 * {@code users.findByEmail(authentication.getName())}, then call {@code requireMedicareAccess} with
 * the {@code patient.id} before returning anything. The unit tests prove what the guard throws;
 * these prove what the caller receives, which is what FR-MCR-17 specifies.
 */
class MedicareAccessPolicyHttpTest {

    /** User ids. */
    private static final long PATIENT = 100L;
    private static final long OTHER_PATIENT = 200L;
    /** Patient record ids, which is what the endpoint is called with; deliberately not the user ids. */
    private static final long PATIENT_RECORD = 10L;
    private static final long OTHER_PATIENT_RECORD = 20L;
    private static final long NO_SUCH_PATIENT_RECORD = 999L;

    /** Stand-in for a Medicare read endpoint: the caller from the principal, the guard, then the data. */
    @RestController
    static class ProbeController {
        private final MedicareAccessPolicy policy;
        private final UserRepository users;

        ProbeController(final MedicareAccessPolicy policy, final UserRepository users) {
            this.policy = policy;
            this.users = users;
        }

        @GetMapping("/probe/{patientId}")
        Map<String, String> read(@PathVariable final Long patientId, final Authentication authentication) {
            final User caller = authentication == null
                    ? null
                    : users.findByEmail(authentication.getName()).orElse(null);
            policy.requireMedicareAccess(caller, patientId);
            return Map.of("records", "visible");
        }
    }

    private final Map<String, User> accounts = new HashMap<>();
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        final UserRepository users = mock(UserRepository.class);
        when(users.findByEmail(anyString())).thenAnswer(inv -> Optional.ofNullable(accounts.get(inv.<String>getArgument(0))));
        final PatientRepository patients = mock(PatientRepository.class);
        when(patients.findById(anyLong())).thenReturn(Optional.empty());
        record(patients, PATIENT_RECORD, PATIENT);
        record(patients, OTHER_PATIENT_RECORD, OTHER_PATIENT);

        // Unstubbed mocks answer false: no caregiver link and no consent grant exist.
        final ProbeController controller = new ProbeController(new MedicareAccessPolicy(
                patients, mock(CaregiverPatientLinkRepository.class), mock(ConsentGrantRepository.class)), users);
        mvc = MockMvcBuilders.standaloneSetup(controller)
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();
    }

    private static void record(final PatientRepository patients, final long recordId, final long userId) {
        final Patient patient = new Patient();
        patient.setId(recordId);
        patient.setUser(User.builder().id(userId).role(Role.PATIENT).build());
        when(patients.findById(recordId)).thenReturn(Optional.of(patient));
    }

    /** An account that can sign in, as the JWT filter would see it: by email. */
    private User account(final long id, final Role role) {
        final User user = User.builder().id(id).email("user-" + id + "@example.test").role(role).build();
        accounts.put(user.getEmail(), user);
        return user;
    }

    private static MockHttpServletRequestBuilder as(final User caller, final long patientId) {
        return get("/probe/" + patientId)
                .principal(new UsernamePasswordAuthenticationToken(caller.getEmail(), null, List.of()));
    }

    private MvcResult request(final User caller, final long patientId) throws Exception {
        return mvc.perform(as(caller, patientId)).andReturn();
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-014 a refusal reaches the caller as HTTP 404 with only the shared message (DEF-MCR-07)")
    void refusalIsA404() throws Exception {
        mvc.perform(as(account(PATIENT, Role.PATIENT), OTHER_PATIENT_RECORD))
                .andExpect(status().isNotFound())
                .andExpect(content().json("{\"error\":\"" + MedicareAccessPolicy.NOT_FOUND_MESSAGE + "\"}", true));
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-015 refusals for different reasons, including a patient that does not exist, "
            + "return the same status and the same body")
    void refusalsAreIndistinguishableOverHttp() throws Exception {
        final List<MvcResult> refusals = new ArrayList<>();
        refusals.add(request(account(PATIENT, Role.PATIENT), OTHER_PATIENT_RECORD));
        refusals.add(request(account(300L, Role.CAREGIVER), PATIENT_RECORD));
        refusals.add(request(account(1L, Role.ADMIN), PATIENT_RECORD));
        refusals.add(request(account(300L, Role.CAREGIVER), NO_SUCH_PATIENT_RECORD));

        for (final MvcResult refusal : refusals) {
            assertThat(refusal.getResponse().getStatus()).isEqualTo(404);
        }
        assertThat(refusals)
                .extracting(r -> r.getResponse().getContentAsString())
                .containsOnly(refusals.get(0).getResponse().getContentAsString());
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-016 an allowed caller, the patient, gets HTTP 200 and the data, by their patient record id")
    void allowedCallerGetsTheData() throws Exception {
        mvc.perform(as(account(PATIENT, Role.PATIENT), PATIENT_RECORD))
                .andExpect(status().isOk())
                .andExpect(content().json("{\"records\":\"visible\"}", true));
    }
}
