package com.careconnect.controller.ehr;

import ca.uhn.fhir.rest.server.exceptions.AuthenticationException;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.MedicareProperties;
import com.careconnect.model.ehr.MedicareSource;
import com.careconnect.model.ehr.MedicareStatusGate;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.ehr.MedicareConnectionService;
import com.careconnect.service.ehr.MedicareConnectionService.MedicareNotConnectedException;
import com.careconnect.service.ehr.EhrService;
import com.careconnect.service.ehr.MedicareRecordCache;
import com.careconnect.service.ehr.MedicareService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.support.StaticListableBeanFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.context.SecurityContextImpl;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * ERR-MCR-05 for the Medicare reads (FR-MCR-09): 409, never 401 (which would sign the app out), and a
 * token Blue Button rejects marks the link Unlinked.
 * <p>
 * Test IDs TC-MCR-LINK-038..044 are permanent. Never renumber, never reuse.
 */
class MedicareErrorAdviceTest {

    private static final String EMAIL = "patient@example.test";

    private MedicareConnectionService connections;
    private UserRepository users;
    private MedicareErrorAdvice advice;

    @BeforeEach
    void setUp() {
        connections = mock(MedicareConnectionService.class);
        users = mock(UserRepository.class);
        advice = new MedicareErrorAdvice(provider(MedicareConnectionService.class, connections),
                provider(UserRepository.class, users));
        SecurityContextHolder.clearContext();
    }

    @AfterEach
    void signOut() {
        SecurityContextHolder.clearContext();
    }

    private static <T> ObjectProvider<T> provider(final Class<T> type, final T bean) {
        final StaticListableBeanFactory beans = new StaticListableBeanFactory();
        if (bean != null) {
            beans.addBean(type.getSimpleName(), bean);
        }
        return beans.getBeanProvider(type);
    }

    private static void signIn() {
        SecurityContextHolder.setContext(new SecurityContextImpl(
                new UsernamePasswordAuthenticationToken(EMAIL, null, List.of())));
    }

    private static void assertErrMcr05(final ResponseEntity<Map<String, Object>> response) {
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(response.getBody())
                .containsEntry("error", "ERR-MCR-05")
                .containsEntry("message", MedicareConnectionService.ERR_MCR_05_MESSAGE)
                .containsEntry("connected", false);
    }

    @Test
    @DisplayName("TC-MCR-LINK-038: no working link is ERR-MCR-05 as 409, and nothing is changed")
    void notConnectedIs409() {
        assertErrMcr05(advice.notConnected(new MedicareNotConnectedException()));
        verifyNoInteractions(connections, users);
    }

    @Test
    @DisplayName("TC-MCR-LINK-039: a token Blue Button rejects marks the signed-in patient's link Unlinked, then answers ERR-MCR-05")
    void rejectedTokenMarksLinkUnlinked() {
        signIn();
        final User user = User.builder().id(6L).email(EMAIL).build();
        when(users.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(connections.patientIdFor(user)).thenReturn(Optional.of(2L));

        assertErrMcr05(advice.tokenRejected(
                new AuthenticationException("401 from Blue Button"), new MockHttpServletRequest()));
        verify(connections).markTokenRejected(2L);
    }

    @Test
    @DisplayName("TC-MCR-LINK-040: a signed-in user with no patient record still gets ERR-MCR-05, and no link is touched")
    void rejectedTokenWithoutPatientTouchesNothing() {
        signIn();
        final User user = User.builder().id(6L).email(EMAIL).build();
        when(users.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(connections.patientIdFor(user)).thenReturn(Optional.empty());

        assertErrMcr05(advice.tokenRejected(new AuthenticationException("401"), new MockHttpServletRequest()));
        verify(connections, never()).markTokenRejected(org.mockito.ArgumentMatchers.any());
    }

    @Test
    @DisplayName("TC-MCR-LINK-041: with nobody signed in, a rejected token is still ERR-MCR-05 and no lookup is made")
    void rejectedTokenWithoutSignIn() {
        assertErrMcr05(advice.tokenRejected(new AuthenticationException("401"), new MockHttpServletRequest()));
        verifyNoInteractions(connections, users);
    }

    @Test
    @DisplayName("TC-MCR-LINK-042: in a context without the Medicare beans (a @WebMvcTest slice) the advice still answers instead of failing")
    void worksWithoutBeans() {
        signIn();
        final MedicareErrorAdvice bare = new MedicareErrorAdvice(
                provider(MedicareConnectionService.class, null), provider(UserRepository.class, null));

        assertErrMcr05(bare.tokenRejected(new AuthenticationException("401"), new MockHttpServletRequest()));
    }

    @Test
    @DisplayName("TC-MCR-LINK-043: a rejected token on a read that names a patient marks that patient's link Unlinked, not the caller's (DEF-MCR-28)")
    void rejectedTokenOnPatientIdReadMarksThatPatient() {
        signIn();
        final MockHttpServletRequest request = new MockHttpServletRequest();
        request.setParameter("patientId", "2");

        assertErrMcr05(advice.tokenRejected(new AuthenticationException("401 from Blue Button"), request));
        verify(connections).markTokenRejected(2L);
        verify(connections, never()).patientIdFor(org.mockito.ArgumentMatchers.any());
    }

    /**
     * A caregiver reading a patient's Medicare data by {@code patientId} (PR #310) whose stored token Blue
     * Button rejects. The token is the patient's, so it is the patient's link that must be set Unlinked
     * (AC-MCR-09-2); the caregiver has no patient record of their own. Through the real
     * {@link EhrController} and this advice, as Spring dispatches them.
     */
    @Test
    @DisplayName("TC-MCR-LINK-044: a token Blue Button rejects during a caregiver's read of a patient marks that patient's link Unlinked (DEF-MCR-28)")
    void caregiverReadRejectedTokenUnlinksThePatient() throws Exception {
        final long patientRecord = 2L;
        final long medicare = 9L;
        final User caregiver = User.builder().id(12L).email(EMAIL).build();
        when(users.findByEmail(EMAIL)).thenReturn(Optional.of(caregiver));
        when(connections.patientIdFor(caregiver)).thenReturn(Optional.empty());

        final MedicareService medicareService = mock(MedicareService.class);
        final EhrService ehrService = mock(EhrService.class);
        final MedicareRecordCache cache = mock(MedicareRecordCache.class);
        final EhrPatientCrosswalk crosswalk = new EhrPatientCrosswalk();
        crosswalk.setPatientId(patientRecord);
        crosswalk.setSourceId(medicare);
        when(medicareService.getId()).thenReturn(medicare);
        when(ehrService.getCrosswalkForPatient(patientRecord, medicare)).thenReturn(Optional.of(crosswalk));
        when(cache.coverage(eq(crosswalk), any())).thenThrow(new AuthenticationException("HTTP 401 from Blue Button"));

        final EhrController controller = new EhrController();
        final MedicareProperties properties = new MedicareProperties();
        ReflectionTestUtils.setField(properties, "mode", MedicareProperties.MODE_LIVE);
        ReflectionTestUtils.setField(controller, "medicareService", medicareService);
        ReflectionTestUtils.setField(controller, "ehrService", ehrService);
        ReflectionTestUtils.setField(controller, "cache", cache);
        ReflectionTestUtils.setField(controller, "properties", properties);
        ReflectionTestUtils.setField(controller, "statusGate", new MedicareStatusGate());
        ReflectionTestUtils.setField(controller, "sources", provider(MedicareSource.class, null));
        final MockMvc mvc = MockMvcBuilders.standaloneSetup(controller).setControllerAdvice(advice).build();
        signIn();

        mvc.perform(get("/v1/api/medicare/coverage").param("patientId", String.valueOf(patientRecord)))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error").value("ERR-MCR-05"));
        verify(connections).markTokenRejected(patientRecord);
    }
}
