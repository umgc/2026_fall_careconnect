package com.careconnect.controller;

import com.careconnect.dto.CaregiverPatientLinkResponse;
import com.careconnect.dto.confirmation.ConfirmationDtos.ConfirmationItemResponse;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.confirmation.ConfirmationService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ConfirmationControllerTest {

    @Mock ConfirmationService confirmationService;
    @Mock SecurityUtil securityUtil;
    @Mock AuthorizationService authorizationService;
    @Mock CaregiverPatientLinkService caregiverPatientLinkService;

    @InjectMocks ConfirmationController controller;

    private User user(boolean admin, boolean caregiver, Long id) {
        User u = mock(User.class);
        lenient().when(u.isAdmin()).thenReturn(admin);
        lenient().when(u.isCaregiver()).thenReturn(caregiver);
        lenient().when(u.getId()).thenReturn(id);
        return u;
    }

    private ConfirmationItemResponse item(Long patientId) {
        return ConfirmationItemResponse.builder().id(1L).patientId(patientId).build();
    }

    private CaregiverPatientLinkResponse link(Long patientUserId) {
        return new CaregiverPatientLinkResponse(1L, 5L, "cg", "cg@x.com", patientUserId,
                "pt", "pt@x.com", "ACTIVE", "PERMANENT", false, false,
                null, null, null, null, true, false);
    }

    @Test
    void getItem_withPatientId_requiresPatientAccess() throws Exception {
        User u = user(false, true, 5L);
        when(securityUtil.resolveCurrentUser()).thenReturn(u);
        when(confirmationService.getItem(1L)).thenReturn(item(42L));

        controller.getItem(1L);

        verify(authorizationService).requirePatientAccess(u, 42L);
    }

    @Test
    void getItem_nullPatientId_fallsBackToAdminOnly() throws Exception {
        User u = user(true, false, 5L);
        when(securityUtil.resolveCurrentUser()).thenReturn(u);
        when(confirmationService.getItem(1L)).thenReturn(item(null));

        controller.getItem(1L);

        verify(authorizationService).requireAdmin(u);
        verify(authorizationService, never()).requireAdminOrCaregiver(any());
    }

    @Test
    void getItem_nullPatientId_deniesCaregiver() throws Exception {
        User u = user(false, true, 5L);
        when(securityUtil.resolveCurrentUser()).thenReturn(u);
        when(confirmationService.getItem(1L)).thenReturn(item(null));
        doThrow(new UnauthorizedException("nope")).when(authorizationService).requireAdmin(u);

        assertThatThrownBy(() -> controller.getItem(1L))
                .isInstanceOf(UnauthorizedException.class);
    }

    @Test
    void confirm_deniedByPatientAccess_doesNotResolve() throws Exception {
        User u = user(false, true, 5L);
        when(securityUtil.resolveCurrentUser()).thenReturn(u);
        when(confirmationService.getItem(1L)).thenReturn(item(42L));
        doThrow(new UnauthorizedException("nope"))
                .when(authorizationService).requirePatientAccess(u, 42L);

        assertThatThrownBy(() -> controller.confirmItem(1L, null))
                .isInstanceOf(UnauthorizedException.class);
        verify(confirmationService, never()).confirm(anyLong(), anyLong(), any());
    }

    @Test
    void listPending_admin_returnsAll() throws Exception {
        User u = user(true, false, 1L);
        when(securityUtil.resolveCurrentUser()).thenReturn(u);
        when(confirmationService.getPendingItems()).thenReturn(List.of(item(42L)));

        var res = controller.listPending(null);

        assertThat(res.getBody()).hasSize(1);
        verify(confirmationService).getPendingItems();
    }

    @Test
    void listPending_caregiver_scopedToLinkedPatients() throws Exception {
        User u = user(false, true, 5L);
        when(securityUtil.resolveCurrentUser()).thenReturn(u);
        when(caregiverPatientLinkService.getPatientsByCaregiver(5L))
                .thenReturn(List.of(link(42L), link(43L)));
        when(confirmationService.getPendingItemsForPatients(List.of(42L, 43L)))
                .thenReturn(List.of(item(42L)));

        var res = controller.listPending(null);

        assertThat(res.getBody()).hasSize(1);
        verify(confirmationService).getPendingItemsForPatients(List.of(42L, 43L));
        verify(confirmationService, never()).getPendingItems();
    }

    @Test
    void listPending_patient_returnsEmpty() throws Exception {
        User u = user(false, false, 9L);
        when(securityUtil.resolveCurrentUser()).thenReturn(u);

        var res = controller.listPending(null);

        assertThat(res.getBody()).isEmpty();
        verify(confirmationService, never()).getPendingItems();
        verify(confirmationService, never()).getPendingItemsForPatients(any());
    }
}
