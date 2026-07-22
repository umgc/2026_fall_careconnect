package com.careconnect.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.dto.AdminAnalyticsSummaryDTO;
import com.careconnect.dto.ErrorMetricsDTO;
import com.careconnect.dto.SyncMetricsDTO;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.AdminAnalyticsService;
import com.careconnect.service.AdminAnalyticsService.TimeRange;
import com.careconnect.util.SecurityUtil;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class AdminAnalyticsControllerTest {

  @Mock private SecurityUtil securityUtil;
  @Mock private AuthorizationService authorizationService;
  @Mock private AdminAnalyticsService adminAnalyticsService;

  @InjectMocks private AdminAnalyticsController controller;

  private final User adminUser = buildUser(Role.ADMIN);
  private final OffsetDateTime from =
      OffsetDateTime.of(2026, 7, 1, 0, 0, 0, 0, ZoneOffset.UTC);
  private final OffsetDateTime to =
      OffsetDateTime.of(2026, 7, 8, 0, 0, 0, 0, ZoneOffset.UTC);

  @Test
  void summary_asAdmin_returnsAggregatedSummary() throws Exception {
    when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);
    when(adminAnalyticsService.resolveRange(7, null, null))
        .thenReturn(new TimeRange(from, to));
    when(adminAnalyticsService.getSummary(from, to)).thenReturn(sampleSummary());

    final AdminAnalyticsSummaryDTO response = controller.summary(7, null, null);

    assertThat(response.totalEvents()).isEqualTo(10L);
    assertThat(response.sessionCount()).isEqualTo(2L);
    verify(authorizationService).requireAdmin(adminUser);
    verify(adminAnalyticsService).getSummary(from, to);
  }

  @Test
  void summary_asAdmin_withExplicitRange_usesResolvedWindow() throws Exception {
    when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);
    when(adminAnalyticsService.resolveRange(null, from, to))
        .thenReturn(new TimeRange(from, to));
    when(adminAnalyticsService.getSummary(from, to)).thenReturn(sampleSummary());

    final AdminAnalyticsSummaryDTO response = controller.summary(null, from, to);

    assertThat(response.periodStart()).isEqualTo(from.toInstant());
    verify(adminAnalyticsService).resolveRange(null, from, to);
  }

  @Test
  void summary_whenNotAdmin_propagatesUnauthorized() throws Exception {
    final User caregiver = buildUser(Role.CAREGIVER);
    when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);
    doThrow(new UnauthorizedException("Admin access required"))
        .when(authorizationService)
        .requireAdmin(caregiver);

    org.junit.jupiter.api.Assertions.assertThrows(
        UnauthorizedException.class, () -> controller.summary(7, null, null));
  }

  private AdminAnalyticsSummaryDTO sampleSummary() {
    return new AdminAnalyticsSummaryDTO(
        Instant.parse("2026-07-01T00:00:00Z"),
        Instant.parse("2026-07-08T00:00:00Z"),
        10L,
        2L,
        List.of(),
        List.of(),
        new SyncMetricsDTO(1L, 1L, 0L, 1L, 1L, 0L, 1.0d),
        new ErrorMetricsDTO(0L, List.of()));
  }

  private static User buildUser(final Role role) {
    final User user = new User();
    user.setId(1L);
    user.setEmail("user@test.com");
    user.setRole(role);
    return user;
  }
}
