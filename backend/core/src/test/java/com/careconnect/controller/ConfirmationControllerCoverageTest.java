package com.careconnect.controller;

import com.careconnect.dto.confirmation.ConfirmationDtos.ConfirmationItemResponse;
import com.careconnect.dto.confirmation.ConfirmationDtos.ResolveConfirmationRequest;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.confirmation.ConfirmationService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class ConfirmationControllerCoverageTest {

    @Mock private ConfirmationService confirmationService;
    @Mock private SecurityUtil securityUtil;
    @Mock private AuthorizationService authorizationService;
    @Mock private CaregiverPatientLinkService caregiverPatientLinkService;

    private ConfirmationController controller;
    private final User caregiver = User.builder().id(3L).role(Role.CAREGIVER).build();

    @BeforeEach
    void setUp() {
        controller = new ConfirmationController(confirmationService, securityUtil, authorizationService,
                caregiverPatientLinkService);
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);
        when(confirmationService.getItem(1L)).thenReturn(ConfirmationItemResponse.builder().id(1L).patientId(9L).build());
        when(confirmationService.getItem(2L)).thenReturn(ConfirmationItemResponse.builder().id(2L).build());
    }

    @Test
    void listPendingPerRole() throws Exception {
        when(caregiverPatientLinkService.getPatientsByCaregiver(3L)).thenReturn(List.of());
        when(confirmationService.getPendingItemsForPatients(anyList())).thenReturn(List.of(
                ConfirmationItemResponse.builder().sourceType("ASK_AI").build(),
                ConfirmationItemResponse.builder().sourceType("SUMMARY").build()));
        assertThat(controller.listPending("ask_ai").getBody()).hasSize(1);

        caregiver.setRole(Role.ADMIN);
        assertThat(controller.listPending("ASK_AI").getStatusCode().value()).isEqualTo(200);
        verify(confirmationService).getPendingItemsBySourceType(any());

        caregiver.setRole(Role.PATIENT);
        assertThat(controller.listPending(null).getBody()).isEmpty();
    }

    @Test
    void resolveItemsAndListByUser() throws Exception {
        assertThat(controller.confirmItem(1L, new ResolveConfirmationRequest("ok")).getStatusCode().value())
                .isEqualTo(200);
        assertThat(controller.confirmItem(2L, null).getStatusCode().value()).isEqualTo(200);
        assertThat(controller.dismissItem(1L, new ResolveConfirmationRequest("no")).getStatusCode().value())
                .isEqualTo(200);
        assertThat(controller.dismissItem(2L, null).getStatusCode().value()).isEqualTo(200);
        assertThat(controller.getItemsByUser(3L).getStatusCode().value()).isEqualTo(200);
        verify(authorizationService).requireSelfOrAdmin(caregiver, 3L);
    }
}
