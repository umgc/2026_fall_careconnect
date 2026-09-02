package com.careconnect.controller;

import com.careconnect.model.Achievement;
import com.careconnect.model.UserAchievement;
import com.careconnect.model.XPProgress;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.GamificationService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class GamificationControllerTest {

    private static final Long USER_ID = 42L;
    @Mock
    private GamificationService gamificationService;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;
    @InjectMocks
    private GamificationController controller;

    // ── awardXp() ─────────────────────────────────────────────────────────────

    @Test
    void awardXp_returns200_withUpdatedProgress() throws Exception {
        final XPProgress progress = mock(XPProgress.class);
        when(gamificationService.awardXp(USER_ID, 50)).thenReturn(progress);

        final Map<String, Object> body = Map.of("userId", USER_ID, "amount", 50);

        final ResponseEntity<?> response = controller.awardXp(body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(progress);
    }

    // ── getXpProgress() ───────────────────────────────────────────────────────

    @Test
    void getXpProgress_returns200_whenProgressFound() throws Exception {
        final XPProgress progress = mock(XPProgress.class);
        when(gamificationService.getXpProgress(USER_ID)).thenReturn(Optional.of(progress));

        final ResponseEntity<?> response = controller.getXpProgress(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(progress);
    }

    @Test
    void getXpProgress_returns404_whenProgressNotFound() throws Exception {
        when(gamificationService.getXpProgress(USER_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.getXpProgress(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.valueOf(404));
    }

    // ── getUserAchievements() ─────────────────────────────────────────────────

    @Test
    void getUserAchievements_returns200_withList() throws Exception {
        final List<UserAchievement> achievements = List.of(mock(UserAchievement.class));
        when(gamificationService.getUserAchievements(USER_ID)).thenReturn(achievements);

        final ResponseEntity<List<UserAchievement>> response = controller.getUserAchievements(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(achievements);
    }

    // ── getAllAchievements() ──────────────────────────────────────────────────

    @Test
    void getAllAchievements_returns200_withList() throws Exception {
        final List<Achievement> achievements = List.of(mock(Achievement.class));
        when(gamificationService.getAllAchievements()).thenReturn(achievements);

        final ResponseEntity<List<Achievement>> response = controller.getAllAchievements();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(achievements);
    }
}
