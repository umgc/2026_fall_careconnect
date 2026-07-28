package com.careconnect.controller;

import com.careconnect.dto.AdminAnalyticsSummaryDTO;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.AdminAnalyticsService;
import com.careconnect.service.AdminAnalyticsService.TimeRange;
import com.careconnect.util.SecurityUtil;
import java.time.OffsetDateTime;
import lombok.RequiredArgsConstructor;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Admin-only anonymous product telemetry analytics. */
@RestController
@RequestMapping("/v1/api/admin/analytics")
@RequiredArgsConstructor
public class AdminAnalyticsController {

  private final SecurityUtil securityUtil;
  private final AuthorizationService authorizationService;
  private final AdminAnalyticsService adminAnalyticsService;

  /**
   * Returns aggregated anonymous telemetry for the requested time window.
   *
   * @param days optional lookback in days (default 7, max 90) when from/to omitted
   * @param from optional inclusive range start (ISO-8601)
   * @param to optional exclusive range end (ISO-8601)
   * @return summary containing counts only; no PII/PHI
   */
  @GetMapping("/summary")
  public AdminAnalyticsSummaryDTO summary(
      @RequestParam(required = false) final Integer days,
      @RequestParam(required = false)
          @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME)
          final OffsetDateTime from,
      @RequestParam(required = false)
          @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME)
          final OffsetDateTime to)
      throws UnauthorizedException {
    final User currentUser = securityUtil.resolveCurrentUser();
    authorizationService.requireAdmin(currentUser);

    final TimeRange range = adminAnalyticsService.resolveRange(days, from, to);
    return adminAnalyticsService.getSummary(range.from(), range.to());
  }
}
