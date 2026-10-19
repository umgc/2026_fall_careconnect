package com.careconnect.controller;

import com.careconnect.dto.visibility.VisibilityDtos.VisibilityRequest;
import com.careconnect.dto.visibility.VisibilityDtos.VisibilityResponse;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.visibility.CaregiverVisibilityService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class CaregiverVisibilityControllerTest {

    private static final Long CG = 5L, PT = 9L;
    @Mock
    CaregiverVisibilityService visibilityService;
    @Mock
    SecurityUtil securityUtil;
    @Mock
    AuthorizationService authorizationService;
    @InjectMocks
    CaregiverVisibilityController controller;

    private User user(boolean admin, Long id) {
        User u = mock(User.class);
        lenient().when(u.isAdmin()).thenReturn(admin);
        lenient().when(u.getId()).thenReturn(id);
        return u;
    }

    private VisibilityRequest req() {
        return VisibilityRequest.builder().caregiverUserId(CG).patientUserId(PT).build();
    }

    @Test
    void grant_deniedWhenNotPatientOrAdmin() throws Exception {
        User u = user(false, CG); // the caregiver, not the patient
        when(securityUtil.resolveCurrentUser()).thenReturn(u);
        doThrow(new UnauthorizedException("no")).when(authorizationService).requireSelfOrAdmin(u, PT);

        assertThatThrownBy(() -> controller.grant(req())).isInstanceOf(UnauthorizedException.class);
        verify(visibilityService, never()).grant(anyLong(), anyLong(), anyLong());
    }

    @Test
    void grant_allowedForPatient() throws Exception {
        User u = user(false, PT); // the patient (consent owner)
        when(securityUtil.resolveCurrentUser()).thenReturn(u);
        when(visibilityService.grant(CG, PT, PT)).thenReturn(VisibilityResponse.builder().build());

        controller.grant(req());

        verify(authorizationService).requireSelfOrAdmin(u, PT);
        verify(visibilityService).grant(CG, PT, PT);
    }

    @Test
    void review_scopesToCaregiverSelfOrAdmin() throws Exception {
        User u = user(false, CG);
        when(securityUtil.resolveCurrentUser()).thenReturn(u);
        when(visibilityService.submitForReview(CG, PT, CG)).thenReturn(VisibilityResponse.builder().build());

        controller.submitForReview(req());

        verify(authorizationService).requireSelfOrAdmin(u, CG);
    }

    @Test
    void getStatus_deniedForUnrelatedUser() throws Exception {
        User u = user(false, 99L); // neither the caregiver nor the patient
        when(securityUtil.resolveCurrentUser()).thenReturn(u);

        assertThatThrownBy(() -> controller.getStatus(CG, PT)).isInstanceOf(UnauthorizedException.class);
        verify(visibilityService, never()).getStatus(anyLong(), anyLong());
    }

    @Test
    void getStatus_allowedForCaregiverInQuestion() throws Exception {
        User u = user(false, CG);
        when(securityUtil.resolveCurrentUser()).thenReturn(u);
        when(visibilityService.getStatus(CG, PT)).thenReturn(VisibilityResponse.builder().build());

        controller.getStatus(CG, PT);

        verify(visibilityService).getStatus(CG, PT);
    }
}
