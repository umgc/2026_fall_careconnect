package com.careconnect.controller;

import com.careconnect.dto.NotificationSettingDTO;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.NotificationSettingService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class NotificationSettingControllerTest {

    private static final Long USER_ID = 1L;
    @Mock
    private NotificationSettingService notificationSettingService;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;
    @InjectMocks
    private NotificationSettingController controller;

    private NotificationSettingDTO makeDto(Long userId) {
        return NotificationSettingDTO.builder()
                .id(10L)
                .userId(userId)
                .gamification(true)
                .emergency(true)
                .videoCall(false)
                .audioCall(false)
                .sms(true)
                .significantVitals(true)
                .createdAt(Instant.now())
                .updatedAt(Instant.now())
                .build();
    }

    // ─── getSettings ──────────────────────────────────────────────────────────

    @Test
    void getSettings_returns200_withDto() throws Exception {
        final NotificationSettingDTO dto = makeDto(USER_ID);
        when(notificationSettingService.getByUserId(USER_ID)).thenReturn(dto);

        final ResponseEntity<NotificationSettingDTO> response = controller.getSettings(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(dto);
    }

    @Test
    void getSettings_returns200_withAllFieldsIntact() throws Exception {
        final NotificationSettingDTO dto = makeDto(USER_ID);
        when(notificationSettingService.getByUserId(USER_ID)).thenReturn(dto);

        final ResponseEntity<NotificationSettingDTO> response = controller.getSettings(USER_ID);

        final NotificationSettingDTO body = response.getBody();
        assertThat(body.userId()).isEqualTo(USER_ID);
        assertThat(body.gamification()).isTrue();
        assertThat(body.emergency()).isTrue();
        assertThat(body.sms()).isTrue();
        assertThat(body.videoCall()).isFalse();
    }

    @Test
    void getSettings_delegatesToServiceWithCorrectUserId() throws Exception {
        final NotificationSettingDTO dto = makeDto(USER_ID);
        when(notificationSettingService.getByUserId(USER_ID)).thenReturn(dto);

        controller.getSettings(USER_ID);

        verify(notificationSettingService).getByUserId(USER_ID);
    }

    // ─── createOrUpdate ───────────────────────────────────────────────────────

    @Test
    void createOrUpdate_returns200_withSavedDto() throws Exception {
        final NotificationSettingDTO input = makeDto(USER_ID);
        final NotificationSettingDTO saved = makeDto(USER_ID);
        when(notificationSettingService.createOrUpdate(input)).thenReturn(saved);

        final ResponseEntity<NotificationSettingDTO> response = controller.createOrUpdate(input);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(saved);
    }

    @Test
    void createOrUpdate_delegatesToServiceWithInput() throws Exception {
        final NotificationSettingDTO input = makeDto(USER_ID);
        when(notificationSettingService.createOrUpdate(input)).thenReturn(input);

        controller.createOrUpdate(input);

        verify(notificationSettingService).createOrUpdate(input);
    }

    @Test
    void createOrUpdate_withAllFalseSettings_returns200() throws Exception {
        final NotificationSettingDTO allFalse = NotificationSettingDTO.builder()
                .id(null)
                .userId(USER_ID)
                .gamification(false)
                .emergency(false)
                .videoCall(false)
                .audioCall(false)
                .sms(false)
                .significantVitals(false)
                .build();
        when(notificationSettingService.createOrUpdate(allFalse)).thenReturn(allFalse);

        final ResponseEntity<NotificationSettingDTO> response = controller.createOrUpdate(allFalse);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody().gamification()).isFalse();
    }
}
