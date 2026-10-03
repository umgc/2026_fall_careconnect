package com.careconnect.security;

import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.model.User;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.ConsentGrantRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * What a refusal from {@link MedicareAccessPolicy} looks like over HTTP, with the application's
 * real {@link GlobalExceptionHandler} in place (WBS 6.2.37; SRS FR-MCR-17, NFR-DEG-03).
 * <p>
 * No Medicare endpoint calls the guard yet, so a stand-in controller does exactly what the PR asks
 * the endpoints to do: call {@code requireMedicareAccess} before returning anything. The unit
 * tests prove what the guard throws; these prove what the caller receives, which is what
 * FR-MCR-17 specifies.
 */
class MedicareAccessPolicyHttpTest {

    private static final long PATIENT = 100L;
    private static final long OTHER_PATIENT = 200L;
    private static final long NO_SUCH_PATIENT = 999L;

    /** Stand-in for a Medicare read endpoint: the guard first, then the data. */
    @RestController
    static class ProbeController {
        private final MedicareAccessPolicy policy;
        private User caller;

        ProbeController(final MedicareAccessPolicy policy) {
            this.policy = policy;
        }

        @GetMapping("/probe/{patientUserId}")
        Map<String, String> read(@PathVariable final Long patientUserId) {
            policy.requireMedicareAccess(caller, patientUserId);
            return Map.of("records", "visible");
        }
    }

    private ProbeController controller;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        // Unstubbed mocks answer false: no caregiver link and no consent grant exist.
        controller = new ProbeController(new MedicareAccessPolicy(
                mock(CaregiverPatientLinkRepository.class), mock(ConsentGrantRepository.class)));
        mvc = MockMvcBuilders.standaloneSetup(controller)
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();
    }

    private static User user(final long id, final Role role) {
        return User.builder().id(id).role(role).build();
    }

    private MvcResult request(final User caller, final long patientUserId) throws Exception {
        controller.caller = caller;
        return mvc.perform(get("/probe/" + patientUserId)).andReturn();
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-014 a refusal reaches the caller as HTTP 404 with only the shared message (DEF-MCR-07)")
    void refusalIsA404() throws Exception {
        controller.caller = user(PATIENT, Role.PATIENT);

        mvc.perform(get("/probe/" + OTHER_PATIENT))
                .andExpect(status().isNotFound())
                .andExpect(content().json("{\"error\":\"" + MedicareAccessPolicy.NOT_FOUND_MESSAGE + "\"}", true));
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-015 refusals for different reasons, including a patient that does not exist, "
            + "return the same status and the same body")
    void refusalsAreIndistinguishableOverHttp() throws Exception {
        final List<MvcResult> refusals = new ArrayList<>();
        refusals.add(request(user(PATIENT, Role.PATIENT), OTHER_PATIENT));
        refusals.add(request(user(300L, Role.CAREGIVER), PATIENT));
        refusals.add(request(user(1L, Role.ADMIN), PATIENT));
        refusals.add(request(user(300L, Role.CAREGIVER), NO_SUCH_PATIENT));

        for (final MvcResult refusal : refusals) {
            assertThat(refusal.getResponse().getStatus()).isEqualTo(404);
        }
        assertThat(refusals)
                .extracting(r -> r.getResponse().getContentAsString())
                .containsOnly(refusals.get(0).getResponse().getContentAsString());
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-016 an allowed caller, the patient, gets HTTP 200 and the data")
    void allowedCallerGetsTheData() throws Exception {
        controller.caller = user(PATIENT, Role.PATIENT);

        mvc.perform(get("/probe/" + PATIENT))
                .andExpect(status().isOk())
                .andExpect(content().json("{\"records\":\"visible\"}", true));
    }
}
