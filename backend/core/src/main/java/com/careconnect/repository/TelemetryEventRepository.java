package com.careconnect.repository;

import com.careconnect.model.TelemetryEvent;
import com.careconnect.repository.projection.EndpointErrorCountProjection;
import com.careconnect.repository.projection.EventNameCountProjection;
import com.careconnect.repository.projection.FeatureUsageCountProjection;
import com.careconnect.repository.projection.SyncCompletedSumProjection;
import java.time.OffsetDateTime;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TelemetryEventRepository extends JpaRepository<TelemetryEvent, Long> {

  /**
   * Returns the 50 most recent telemetry events.
   *
   * @return most recent telemetry events in descending time order
   */
  List<TelemetryEvent> findTop50ByOrderByEventTimeDesc();

  @Query(
      value =
          """
          SELECT COUNT(*)
          FROM telemetry_events
          WHERE event_time >= :from AND event_time < :to
          """,
      nativeQuery = true)
  long countTotalEventsBetween(
      @Param("from") OffsetDateTime from, @Param("to") OffsetDateTime to);

  @Query(
      value =
          """
          SELECT COUNT(DISTINCT session_id)
          FROM telemetry_events
          WHERE event_time >= :from AND event_time < :to
            AND session_id IS NOT NULL
          """,
      nativeQuery = true)
  long countDistinctSessionsBetween(
      @Param("from") OffsetDateTime from, @Param("to") OffsetDateTime to);

  @Query(
      value =
          """
          SELECT event_name AS eventName, COUNT(*) AS count
          FROM telemetry_events
          WHERE event_time >= :from AND event_time < :to
          GROUP BY event_name
          ORDER BY count DESC
          LIMIT 20
          """,
      nativeQuery = true)
  List<EventNameCountProjection> countByEventNameBetween(
      @Param("from") OffsetDateTime from, @Param("to") OffsetDateTime to);

  @Query(
      value =
          """
          SELECT details->>'feature' AS feature, COUNT(*) AS count
          FROM telemetry_events
          WHERE event_time >= :from AND event_time < :to
            AND event_name = 'feature_use'
            AND details->>'feature' IS NOT NULL
            AND length(details->>'feature') <= 64
          GROUP BY details->>'feature'
          ORDER BY count DESC
          LIMIT 10
          """,
      nativeQuery = true)
  List<FeatureUsageCountProjection> countTopFeaturesBetween(
      @Param("from") OffsetDateTime from, @Param("to") OffsetDateTime to);

  @Query(
      value =
          """
          SELECT COUNT(*)
          FROM telemetry_events
          WHERE event_time >= :from AND event_time < :to
            AND event_name = :eventName
          """,
      nativeQuery = true)
  long countEventsNamedBetween(
      @Param("eventName") String eventName,
      @Param("from") OffsetDateTime from,
      @Param("to") OffsetDateTime to);

  @Query(
      value =
          """
          SELECT
            COALESCE(SUM((details->>'attempted')::bigint), 0) AS attempted,
            COALESCE(SUM((details->>'succeeded')::bigint), 0) AS succeeded,
            COALESCE(SUM((details->>'failed')::bigint), 0) AS failed
          FROM telemetry_events
          WHERE event_time >= :from AND event_time < :to
            AND event_name = 'sync_completed'
          """,
      nativeQuery = true)
  SyncCompletedSumProjection sumSyncCompletedBetween(
      @Param("from") OffsetDateTime from, @Param("to") OffsetDateTime to);

  @Query(
      value =
          """
          SELECT details->>'endpoint' AS endpoint, COUNT(*) AS count
          FROM telemetry_events
          WHERE event_time >= :from AND event_time < :to
            AND event_name IN ('error_network', 'error_timeout')
            AND details->>'endpoint' IS NOT NULL
            AND length(details->>'endpoint') <= 64
          GROUP BY details->>'endpoint'
          ORDER BY count DESC
          LIMIT 10
          """,
      nativeQuery = true)
  List<EndpointErrorCountProjection> countErrorsByEndpointBetween(
      @Param("from") OffsetDateTime from, @Param("to") OffsetDateTime to);
}
