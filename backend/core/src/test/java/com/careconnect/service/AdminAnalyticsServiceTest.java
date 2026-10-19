package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import com.careconnect.dto.AdminAnalyticsSummaryDTO;
import com.careconnect.dto.FeatureTrendDTO;
import com.careconnect.exception.AppException;
import com.careconnect.repository.TelemetryEventRepository;
import com.careconnect.repository.projection.DailyFeatureCountProjection;
import com.careconnect.repository.projection.EndpointErrorCountProjection;
import com.careconnect.repository.projection.EventNameCountProjection;
import com.careconnect.repository.projection.FeatureUsageCountProjection;
import com.careconnect.repository.projection.SyncCompletedSumProjection;

import java.time.Clock;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;

import org.assertj.core.data.Offset;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class AdminAnalyticsServiceTest {

    private final OffsetDateTime from =
            OffsetDateTime.of(2026, 7, 1, 0, 0, 0, 0, ZoneOffset.UTC);
    private final OffsetDateTime to =
            OffsetDateTime.of(2026, 7, 8, 0, 0, 0, 0, ZoneOffset.UTC);
    @Mock
    private TelemetryEventRepository telemetryEventRepository;
    private AdminAnalyticsService service;

    private static EventNameCountProjection eventNameRow(final String name, final long count) {
        return new EventNameCountProjection() {
            @Override
            public String getEventName() {
                return name;
            }

            @Override
            public Number getCount() {
                return count;
            }
        };
    }

    private static FeatureUsageCountProjection featureRow(final String feature, final long count) {
        return new FeatureUsageCountProjection() {
            @Override
            public String getFeature() {
                return feature;
            }

            @Override
            public Number getCount() {
                return count;
            }
        };
    }

    private static EndpointErrorCountProjection endpointRow(
            final String endpoint, final long count) {
        return new EndpointErrorCountProjection() {
            @Override
            public String getEndpoint() {
                return endpoint;
            }

            @Override
            public Number getCount() {
                return count;
            }
        };
    }

    private static SyncCompletedSumProjection syncSumRow(
            final long attempted, final long succeeded, final long failed) {
        return new SyncCompletedSumProjection() {
            @Override
            public Number getAttempted() {
                return attempted;
            }

            @Override
            public Number getSucceeded() {
                return succeeded;
            }

            @Override
            public Number getFailed() {
                return failed;
            }
        };
    }

    private static DailyFeatureCountProjection dailyRow(final String day, final long count) {
        return new DailyFeatureCountProjection() {
            @Override
            public String getDay() {
                return day;
            }

            @Override
            public Number getCount() {
                return count;
            }
        };
    }

    @BeforeEach
    void setUp() {
        service = new AdminAnalyticsService(telemetryEventRepository, Clock.systemUTC());
    }

    @Test
    void getSummary_withNoEvents_returnsZerosAndEmptyLists() {
        stubEmptyRepository();

        final AdminAnalyticsSummaryDTO summary = service.getSummary(from, to);

        assertThat(summary.totalEvents()).isZero();
        assertThat(summary.sessionCount()).isZero();
        assertThat(summary.eventCountsByName()).isEmpty();
        assertThat(summary.topFeatures()).isEmpty();
        assertThat(summary.syncMetrics().successRate()).isNull();
        assertThat(summary.errorMetrics().totalErrors()).isZero();
        assertThat(summary.errorMetrics().byEndpointBucket()).isEmpty();
    }

    @Test
    void getSummary_computesSyncSuccessRateAndErrorRates() {
        when(telemetryEventRepository.countTotalEventsBetween(from, to)).thenReturn(12L);
        when(telemetryEventRepository.countDistinctSessionsBetween(from, to)).thenReturn(3L);
        when(telemetryEventRepository.countByEventNameBetween(from, to))
                .thenReturn(List.of(eventNameRow("feature_use", 4L)));
        when(telemetryEventRepository.countTopFeaturesBetween(from, to))
                .thenReturn(List.of(featureRow("chat_room", 4L)));
        when(telemetryEventRepository.countEventsNamedBetween("sync_started", from, to))
                .thenReturn(2L);
        when(telemetryEventRepository.countEventsNamedBetween("sync_completed", from, to))
                .thenReturn(2L);
        when(telemetryEventRepository.countEventsNamedBetween("sync_failed", from, to))
                .thenReturn(1L);
        when(telemetryEventRepository.sumSyncCompletedBetween(from, to))
                .thenReturn(syncSumRow(5L, 4L, 1L));
        when(telemetryEventRepository.countErrorsByEndpointBetween(from, to))
                .thenReturn(
                        List.of(
                                endpointRow("patients", 2L),
                                endpointRow("evv", 1L)));

        final AdminAnalyticsSummaryDTO summary = service.getSummary(from, to);

        assertThat(summary.syncMetrics().started()).isEqualTo(2L);
        assertThat(summary.syncMetrics().succeeded()).isEqualTo(4L);
        assertThat(summary.syncMetrics().failed()).isEqualTo(1L);
        assertThat(summary.syncMetrics().successRate()).isEqualTo(0.8d);
        assertThat(summary.errorMetrics().totalErrors()).isEqualTo(3L);
        assertThat(summary.errorMetrics().byEndpointBucket()).hasSize(2);
        assertThat(summary.errorMetrics().byEndpointBucket().get(0).endpoint()).isEqualTo("patients");
        assertThat(summary.errorMetrics().byEndpointBucket().get(0).rate())
                .isCloseTo(2.0 / 3.0, Offset.offset(0.001));
        assertThat(summary.topFeatures().get(0).feature()).isEqualTo("chat_room");
    }

    @Test
    void getSummary_rejectsInvalidRange() {
        assertThatThrownBy(() -> service.getSummary(to, from))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("from must be before to");
    }

    @Test
    void getSummary_rejectsRangeLongerThan90Days() {
        final OffsetDateTime longFrom = to.minusDays(91);

        assertThatThrownBy(() -> service.getSummary(longFrom, to))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("90 days");
    }

    @Test
    void resolveRange_defaultsToSevenDaysWhenUnset() {
        final AdminAnalyticsService.TimeRange range = service.resolveRange(null, null, null);

        assertThat(range.from()).isBefore(range.to());
        assertThat(range.to().toInstant()).isNotNull();
    }

    @Test
    void getSummary_filtersUnsafeFeatureNames() {
        stubEmptyRepository();
        when(telemetryEventRepository.countTopFeaturesBetween(from, to))
                .thenReturn(
                        List.of(
                                featureRow("chat_room", 2L),
                                featureRow("bad feature name!", 9L)));

        final AdminAnalyticsSummaryDTO summary = service.getSummary(from, to);

        assertThat(summary.topFeatures()).hasSize(1);
        assertThat(summary.topFeatures().get(0).feature()).isEqualTo("chat_room");
    }

    @Test
    void getFeatureTrends_zeroFillsMissingDays() {
        when(telemetryEventRepository.countFeatureUseByDayBetween(from, to, "dashboard"))
                .thenReturn(
                        List.of(
                                dailyRow("2026-07-01", 5L),
                                dailyRow("2026-07-03", 2L)));

        final FeatureTrendDTO trend = service.getFeatureTrends(from, to, "dashboard");

        assertThat(trend.feature()).isEqualTo("dashboard");
        assertThat(trend.periodStart()).isEqualTo(from.toInstant());
        assertThat(trend.periodEnd()).isEqualTo(to.toInstant());
        assertThat(trend.dailyCounts()).hasSize(7);
        assertThat(trend.dailyCounts().get(0).date()).isEqualTo("2026-07-01");
        assertThat(trend.dailyCounts().get(0).count()).isEqualTo(5L);
        assertThat(trend.dailyCounts().get(1).date()).isEqualTo("2026-07-02");
        assertThat(trend.dailyCounts().get(1).count()).isZero();
        assertThat(trend.dailyCounts().get(2).count()).isEqualTo(2L);
        assertThat(trend.dailyCounts().get(6).date()).isEqualTo("2026-07-07");
    }

    @Test
    void getFeatureTrends_rejectsInvalidFeatureName() {
        assertThatThrownBy(() -> service.getFeatureTrends(from, to, "bad feature!"))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("Invalid feature name");
    }

    @Test
    void getFeatureTrends_rejectsInvalidRange() {
        assertThatThrownBy(() -> service.getFeatureTrends(to, from, "dashboard"))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("from must be before to");
    }

    private void stubEmptyRepository() {
        when(telemetryEventRepository.countTotalEventsBetween(any(), any())).thenReturn(0L);
        when(telemetryEventRepository.countDistinctSessionsBetween(any(), any())).thenReturn(0L);
        when(telemetryEventRepository.countByEventNameBetween(any(), any())).thenReturn(List.of());
        when(telemetryEventRepository.countTopFeaturesBetween(any(), any())).thenReturn(List.of());
        when(telemetryEventRepository.countEventsNamedBetween(eq("sync_started"), any(), any()))
                .thenReturn(0L);
        when(telemetryEventRepository.countEventsNamedBetween(eq("sync_completed"), any(), any()))
                .thenReturn(0L);
        when(telemetryEventRepository.countEventsNamedBetween(eq("sync_failed"), any(), any()))
                .thenReturn(0L);
        when(telemetryEventRepository.sumSyncCompletedBetween(any(), any())).thenReturn(syncSumRow(0L, 0L, 0L));
        when(telemetryEventRepository.countErrorsByEndpointBetween(any(), any())).thenReturn(List.of());
    }
}
