/// One activity enabled for a client (from GET /clients/{id}/activities).
class ClientActivity {
  final int id;
  final String name;
  final String category; // ADL | IADL
  final String? customIconUrl;
  final String? defaultIconUrl;
  final bool enabled;

  const ClientActivity({
    required this.id,
    required this.name,
    required this.category,
    this.customIconUrl,
    this.defaultIconUrl,
    this.enabled = true,
  });

  static ClientActivity fromJson(Map<String, dynamic> json) {
    return ClientActivity(
      id: (json['id'] is int)
          ? json['id'] as int
          : int.tryParse(json['id'].toString()) ?? 0,
      name: json['name']?.toString() ?? '',
      category: (json['category']?.toString() ?? 'ADL').toUpperCase(),
      customIconUrl: json['customIconUrl']?.toString(),
      defaultIconUrl: json['defaultIconUrl']?.toString(),
      enabled: json['enabled'] == true,
    );
  }
}

/// One option in the competency scale (from GET /config/competency-scale).
class CompetencyScaleItem {
  final int value;
  final String label;

  const CompetencyScaleItem({required this.value, required this.label});

  static CompetencyScaleItem fromJson(Map<String, dynamic> json) {
    return CompetencyScaleItem(
      value: (json['value'] is int)
          ? json['value'] as int
          : int.tryParse(json['value'].toString()) ?? 0,
      label: json['label']?.toString() ?? '',
    );
  }
}

/// Master activity definition from GET /activities (all activities for a category).
class Activity {
  final int id;
  final String name;
  final String category;
  final String? defaultIconUrl;

  const Activity({
    required this.id,
    required this.name,
    required this.category,
    this.defaultIconUrl,
  });

  static Activity fromJson(Map<String, dynamic> json) {
    return Activity(
      id: (json['id'] is int)
          ? json['id'] as int
          : int.tryParse(json['id'].toString()) ?? 0,
      name: json['name']?.toString() ?? '',
      category: (json['category']?.toString() ?? 'ADL').toUpperCase(),
      defaultIconUrl: json['defaultIconUrl']?.toString(),
    );
  }
}

/// One activity log entry (from GET /activity-logs).
class ActivityLogEntry {
  final int id;
  final int clientId;
  final int activityId;
  final String? activityName;
  final int competencyScore;
  final int? satisfactionRating;
  final String? notes;
  final DateTime createdAt;

  const ActivityLogEntry({
    required this.id,
    required this.clientId,
    required this.activityId,
    this.activityName,
    required this.competencyScore,
    this.satisfactionRating,
    this.notes,
    required this.createdAt,
  });

  static ActivityLogEntry fromJson(Map<String, dynamic> json) {
    DateTime createdAt = DateTime.now();
    final createdAtRaw = json['createdAt'];
    if (createdAtRaw != null) {
      if (createdAtRaw is String) {
        createdAt = DateTime.tryParse(createdAtRaw) ?? createdAt;
      } else if (createdAtRaw is List && createdAtRaw.length >= 6) {
        final y = createdAtRaw[0] is int
            ? createdAtRaw[0] as int
            : int.tryParse(createdAtRaw[0].toString()) ?? 0;
        final m = createdAtRaw[1] is int
            ? createdAtRaw[1] as int
            : int.tryParse(createdAtRaw[1].toString()) ?? 1;
        final d = createdAtRaw[2] is int
            ? createdAtRaw[2] as int
            : int.tryParse(createdAtRaw[2].toString()) ?? 1;
        final h = createdAtRaw.length > 3 && createdAtRaw[3] != null
            ? (createdAtRaw[3] is int
                ? createdAtRaw[3] as int
                : int.tryParse(createdAtRaw[3].toString()) ?? 0)
            : 0;
        final min = createdAtRaw.length > 4 && createdAtRaw[4] != null
            ? (createdAtRaw[4] is int
                ? createdAtRaw[4] as int
                : int.tryParse(createdAtRaw[4].toString()) ?? 0)
            : 0;
        final sec = createdAtRaw.length > 5 && createdAtRaw[5] != null
            ? (createdAtRaw[5] is int
                ? createdAtRaw[5] as int
                : int.tryParse(createdAtRaw[5].toString()) ?? 0)
            : 0;
        createdAt = DateTime(y, m.clamp(1, 12), d.clamp(1, 31), h, min, sec);
      }
    }
    return ActivityLogEntry(
      id: (json['id'] is int)
          ? json['id'] as int
          : int.tryParse(json['id'].toString()) ?? 0,
      clientId: (json['clientId'] is int)
          ? json['clientId'] as int
          : int.tryParse(json['clientId'].toString()) ?? 0,
      activityId: (json['activityId'] is int)
          ? json['activityId'] as int
          : int.tryParse(json['activityId'].toString()) ?? 0,
      activityName: json['activityName']?.toString(),
      competencyScore: (json['competencyScore'] is int)
          ? json['competencyScore'] as int
          : int.tryParse(json['competencyScore'].toString()) ?? 0,
      satisfactionRating: json['satisfactionRating'] != null
          ? ((json['satisfactionRating'] is int)
              ? json['satisfactionRating'] as int
              : int.tryParse(json['satisfactionRating'].toString()))
          : null,
      notes: json['notes']?.toString(),
      createdAt: createdAt,
    );
  }
}

/// One behavioral incident entry (from GET /clients/{id}/behavioral-incidents).
class BehavioralIncidentEntry {
  final int id;
  final int clientId;
  final int caregiverId;
  final String observedBehavior;
  final DateTime occurredAt;
  final String? triggerNotes;

  const BehavioralIncidentEntry({
    required this.id,
    required this.clientId,
    required this.caregiverId,
    required this.observedBehavior,
    required this.occurredAt,
    this.triggerNotes,
  });

  static BehavioralIncidentEntry fromJson(Map<String, dynamic> json) {
    DateTime occurredAt = DateTime.now();
    final occurredRaw = json['occurredAt'] ?? json['occurred_at'];
    if (occurredRaw != null) {
      if (occurredRaw is String) {
        occurredAt = DateTime.tryParse(occurredRaw) ?? occurredAt;
      } else if (occurredRaw is List && occurredRaw.length >= 3) {
        final y = occurredRaw[0] is int
            ? occurredRaw[0] as int
            : int.tryParse(occurredRaw[0].toString()) ?? 0;
        final m = occurredRaw[1] is int
            ? occurredRaw[1] as int
            : int.tryParse(occurredRaw[1].toString()) ?? 1;
        final d = occurredRaw[2] is int
            ? occurredRaw[2] as int
            : int.tryParse(occurredRaw[2].toString()) ?? 1;
        final h = occurredRaw.length > 3 && occurredRaw[3] != null
            ? (occurredRaw[3] is int
                ? occurredRaw[3] as int
                : int.tryParse(occurredRaw[3].toString()) ?? 0)
            : 0;
        final min = occurredRaw.length > 4 && occurredRaw[4] != null
            ? (occurredRaw[4] is int
                ? occurredRaw[4] as int
                : int.tryParse(occurredRaw[4].toString()) ?? 0)
            : 0;
        final sec = occurredRaw.length > 5 && occurredRaw[5] != null
            ? (occurredRaw[5] is int
                ? occurredRaw[5] as int
                : int.tryParse(occurredRaw[5].toString()) ?? 0)
            : 0;
        occurredAt = DateTime(y, m.clamp(1, 12), d.clamp(1, 31), h, min, sec);
      }
    }
    return BehavioralIncidentEntry(
      id: (json['id'] is int)
          ? json['id'] as int
          : int.tryParse(json['id'].toString()) ?? 0,
      clientId: (json['clientId'] is int)
          ? json['clientId'] as int
          : int.tryParse(json['clientId'].toString()) ?? 0,
      caregiverId: (json['caregiverId'] is int)
          ? json['caregiverId'] as int
          : int.tryParse(json['caregiverId'].toString()) ?? 0,
      observedBehavior: json['observedBehavior']?.toString() ??
          json['observed_behavior']?.toString() ??
          '',
      occurredAt: occurredAt,
      triggerNotes:
          json['triggerNotes']?.toString() ?? json['trigger_notes']?.toString(),
    );
  }
}

/// One structured incident report entry (from GET /clients/{id}/incident-reports).
class IncidentReportEntry {
  final int id;
  final int clientId;
  final int caregiverId;
  final String incidentType; // Enum string from backend
  final DateTime occurredAt;
  final String location;
  final String? triggerNotes;
  final String outcome;
  final DateTime createdAt;
  final List<String> actions;

  const IncidentReportEntry({
    required this.id,
    required this.clientId,
    required this.caregiverId,
    required this.incidentType,
    required this.occurredAt,
    required this.location,
    this.triggerNotes,
    required this.outcome,
    required this.createdAt,
    required this.actions,
  });

  static IncidentReportEntry fromJson(Map<String, dynamic> json) {
    DateTime occurredAt = DateTime.now();
    final occurredRaw = json['occurredAt'] ?? json['occurred_at'];
    if (occurredRaw != null) {
      if (occurredRaw is String) {
        occurredAt = DateTime.tryParse(occurredRaw) ?? occurredAt;
      } else if (occurredRaw is List && occurredRaw.length >= 3) {
        final y = occurredRaw[0] is int
            ? occurredRaw[0] as int
            : int.tryParse(occurredRaw[0].toString()) ?? 0;
        final m = occurredRaw[1] is int
            ? occurredRaw[1] as int
            : int.tryParse(occurredRaw[1].toString()) ?? 1;
        final d = occurredRaw[2] is int
            ? occurredRaw[2] as int
            : int.tryParse(occurredRaw[2].toString()) ?? 1;
        final h = occurredRaw.length > 3 && occurredRaw[3] != null
            ? (occurredRaw[3] is int
                ? occurredRaw[3] as int
                : int.tryParse(occurredRaw[3].toString()) ?? 0)
            : 0;
        final min = occurredRaw.length > 4 && occurredRaw[4] != null
            ? (occurredRaw[4] is int
                ? occurredRaw[4] as int
                : int.tryParse(occurredRaw[4].toString()) ?? 0)
            : 0;
        final sec = occurredRaw.length > 5 && occurredRaw[5] != null
            ? (occurredRaw[5] is int
                ? occurredRaw[5] as int
                : int.tryParse(occurredRaw[5].toString()) ?? 0)
            : 0;
        occurredAt = DateTime(y, m.clamp(1, 12), d.clamp(1, 31), h, min, sec);
      }
    }

    DateTime createdAt = DateTime.now();
    final createdRaw = json['createdAt'] ?? json['created_at'];
    if (createdRaw != null) {
      if (createdRaw is String) {
        createdAt = DateTime.tryParse(createdRaw) ?? createdAt;
      } else if (createdRaw is List && createdRaw.length >= 3) {
        final y = createdRaw[0] is int
            ? createdRaw[0] as int
            : int.tryParse(createdRaw[0].toString()) ?? 0;
        final m = createdRaw[1] is int
            ? createdRaw[1] as int
            : int.tryParse(createdRaw[1].toString()) ?? 1;
        final d = createdRaw[2] is int
            ? createdRaw[2] as int
            : int.tryParse(createdRaw[2].toString()) ?? 1;
        final h = createdRaw.length > 3 && createdRaw[3] != null
            ? (createdRaw[3] is int
                ? createdRaw[3] as int
                : int.tryParse(createdRaw[3].toString()) ?? 0)
            : 0;
        final min = createdRaw.length > 4 && createdRaw[4] != null
            ? (createdRaw[4] is int
                ? createdRaw[4] as int
                : int.tryParse(createdRaw[4].toString()) ?? 0)
            : 0;
        final sec = createdRaw.length > 5 && createdRaw[5] != null
            ? (createdRaw[5] is int
                ? createdRaw[5] as int
                : int.tryParse(createdRaw[5].toString()) ?? 0)
            : 0;
        createdAt = DateTime(y, m.clamp(1, 12), d.clamp(1, 31), h, min, sec);
      }
    }

    List<String> actions = [];
    final actionsRaw = json['actions'];
    if (actionsRaw is List) {
      for (final item in actionsRaw) {
        if (item is Map && item['actionTaken'] != null) {
          final t = item['actionTaken'].toString().trim();
          if (t.isNotEmpty) actions.add(t);
        } else if (item != null) {
          final t = item.toString().trim();
          if (t.isNotEmpty) actions.add(t);
        }
      }
    }

    return IncidentReportEntry(
      id: (json['id'] is int)
          ? json['id'] as int
          : int.tryParse(json['id'].toString()) ?? 0,
      clientId: (json['clientId'] is int)
          ? json['clientId'] as int
          : int.tryParse(json['clientId'].toString()) ?? 0,
      caregiverId: (json['caregiverId'] is int)
          ? json['caregiverId'] as int
          : int.tryParse(json['caregiverId'].toString()) ?? 0,
      incidentType: json['incidentType']?.toString() ??
          json['incident_type']?.toString() ??
          '',
      occurredAt: occurredAt,
      location: json['location']?.toString() ?? '',
      triggerNotes:
          json['triggerNotes']?.toString() ?? json['trigger_notes']?.toString(),
      outcome: json['outcome']?.toString() ?? '',
      createdAt: createdAt,
      actions: actions,
    );
  }
}

// --- Competency Trends Report (GET /clients/{id}/reports/competency-trends) ---

class CompetencyWeekDataPoint {
  final String weekStartDate;
  final double averageCompetencyScore;
  final int logCount;

  const CompetencyWeekDataPoint({
    required this.weekStartDate,
    required this.averageCompetencyScore,
    required this.logCount,
  });

  static CompetencyWeekDataPoint fromJson(Map<String, dynamic> json) {
    return CompetencyWeekDataPoint(
      weekStartDate: json['weekStartDate']?.toString() ?? '',
      averageCompetencyScore: (json['averageCompetencyScore'] is num)
          ? (json['averageCompetencyScore'] as num).toDouble()
          : 0.0,
      logCount: (json['logCount'] is int)
          ? json['logCount'] as int
          : int.tryParse(json['logCount'].toString()) ?? 0,
    );
  }
}

class CompetencyActivityTrend {
  final int activityId;
  final String activityName;
  final List<CompetencyWeekDataPoint> dataPoints;

  const CompetencyActivityTrend({
    required this.activityId,
    required this.activityName,
    required this.dataPoints,
  });

  static CompetencyActivityTrend fromJson(Map<String, dynamic> json) {
    final raw = json['dataPoints'];
    final points = raw is List
        ? (raw)
            .whereType<Map<String, dynamic>>()
            .map(CompetencyWeekDataPoint.fromJson)
            .toList()
        : <CompetencyWeekDataPoint>[];
    return CompetencyActivityTrend(
      activityId: (json['activityId'] is int)
          ? json['activityId'] as int
          : int.tryParse(json['activityId'].toString()) ?? 0,
      activityName: json['activityName']?.toString() ?? '',
      dataPoints: points,
    );
  }
}

class CompetencyTrendsResponse {
  final String status; // IMPROVING | STABLE | DECLINING
  final List<String> weekLabels;
  final List<CompetencyActivityTrend> activityTrends;

  const CompetencyTrendsResponse({
    required this.status,
    required this.weekLabels,
    required this.activityTrends,
  });

  static CompetencyTrendsResponse fromJson(Map<String, dynamic> json) {
    final rawWeeks = json['weekLabels'];
    final weekLabels = rawWeeks is List
        ? (rawWeeks).whereType<String>().toList()
        : (rawWeeks is List
            ? (rawWeeks).map((e) => e?.toString() ?? '').toList()
            : <String>[]);
    final rawTrends = json['activityTrends'];
    final activityTrends = rawTrends is List
        ? (rawTrends)
            .whereType<Map<String, dynamic>>()
            .map(CompetencyActivityTrend.fromJson)
            .toList()
        : <CompetencyActivityTrend>[];
    return CompetencyTrendsResponse(
      status: json['status']?.toString() ?? 'STABLE',
      weekLabels: weekLabels,
      activityTrends: activityTrends,
    );
  }
}

// --- Behavioral Trends Report (GET /clients/{id}/reports/behavioral-trends) ---

class BehavioralTrendsResponse {
  final String trend; // UP | STABLE | DOWN
  final List<BehavioralWeekCount> weeklyCounts;
  final List<String> topKeywords;

  const BehavioralTrendsResponse({
    required this.trend,
    required this.weeklyCounts,
    required this.topKeywords,
  });

  static BehavioralTrendsResponse fromJson(Map<String, dynamic> json) {
    final raw = json['weeklyCounts'];
    final weeklyCounts = raw is List
        ? (raw)
            .whereType<Map<String, dynamic>>()
            .map(BehavioralWeekCount.fromJson)
            .toList()
        : <BehavioralWeekCount>[];
    final rawKw = json['topKeywords'];
    final topKeywords = rawKw is List
        ? (rawKw)
            .map((e) => e?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList()
        : <String>[];
    return BehavioralTrendsResponse(
      trend: json['trend']?.toString() ?? 'STABLE',
      weeklyCounts: weeklyCounts,
      topKeywords: topKeywords,
    );
  }
}

class BehavioralWeekCount {
  final String weekStartDate;
  final int incidentCount;

  const BehavioralWeekCount(
      {required this.weekStartDate, required this.incidentCount});

  static BehavioralWeekCount fromJson(Map<String, dynamic> json) {
    return BehavioralWeekCount(
      weekStartDate: json['weekStartDate']?.toString() ?? '',
      incidentCount: (json['incidentCount'] is int)
          ? json['incidentCount'] as int
          : int.tryParse(json['incidentCount'].toString()) ?? 0,
    );
  }
}

// --- Participation Report (GET /clients/{id}/reports/participation) ---

class ParticipationResponse {
  final String status; // IMPROVING | STABLE | DECLINING
  final List<ParticipationWeekCount> weeklyCounts;
  final List<ActivityParticipation> activities;

  const ParticipationResponse({
    required this.status,
    required this.weeklyCounts,
    required this.activities,
  });

  static ParticipationResponse fromJson(Map<String, dynamic> json) {
    final rawWeeks = json['weeklyCounts'];
    final weeklyCounts = rawWeeks is List
        ? (rawWeeks)
            .whereType<Map<String, dynamic>>()
            .map(ParticipationWeekCount.fromJson)
            .toList()
        : <ParticipationWeekCount>[];
    final raw = json['activities'];
    final activities = raw is List
        ? (raw)
            .whereType<Map<String, dynamic>>()
            .map(ActivityParticipation.fromJson)
            .toList()
        : <ActivityParticipation>[];
    return ParticipationResponse(
      status: json['status']?.toString() ?? 'STABLE',
      weeklyCounts: weeklyCounts,
      activities: activities,
    );
  }
}

class ParticipationWeekCount {
  final String weekStartDate;
  final int totalLogs;

  const ParticipationWeekCount(
      {required this.weekStartDate, required this.totalLogs});

  static ParticipationWeekCount fromJson(Map<String, dynamic> json) {
    return ParticipationWeekCount(
      weekStartDate: json['weekStartDate']?.toString() ?? '',
      totalLogs: (json['totalLogs'] is int)
          ? json['totalLogs'] as int
          : int.tryParse(json['totalLogs'].toString()) ?? 0,
    );
  }
}

class ActivityParticipation {
  final int activityId;
  final String activityName;
  final String category; // ADL | IADL
  final int totalLogsInPeriod;
  final DateTime? lastLoggedAt;
  final bool noRecentActivity;

  const ActivityParticipation({
    required this.activityId,
    required this.activityName,
    required this.category,
    required this.totalLogsInPeriod,
    this.lastLoggedAt,
    required this.noRecentActivity,
  });

  static ActivityParticipation fromJson(Map<String, dynamic> json) {
    DateTime? lastLoggedAt;
    final raw = json['lastLoggedAt'];
    if (raw != null) {
      if (raw is String) {
        lastLoggedAt = DateTime.tryParse(raw);
      } else if (raw is List && raw.length >= 6) {
        final y = raw[0] is int
            ? raw[0] as int
            : int.tryParse(raw[0].toString()) ?? 0;
        final m = (raw[1] is int
                ? raw[1] as int
                : int.tryParse(raw[1].toString()) ?? 1)
            .clamp(1, 12);
        final d = (raw[2] is int
                ? raw[2] as int
                : int.tryParse(raw[2].toString()) ?? 1)
            .clamp(1, 31);
        final h = raw.length > 3 && raw[3] != null
            ? (raw[3] is int
                ? raw[3] as int
                : int.tryParse(raw[3].toString()) ?? 0)
            : 0;
        final min = raw.length > 4 && raw[4] != null
            ? (raw[4] is int
                ? raw[4] as int
                : int.tryParse(raw[4].toString()) ?? 0)
            : 0;
        final sec = raw.length > 5 && raw[5] != null
            ? (raw[5] is int
                ? raw[5] as int
                : int.tryParse(raw[5].toString()) ?? 0)
            : 0;
        lastLoggedAt = DateTime(y, m, d, h, min, sec);
      }
    }
    return ActivityParticipation(
      activityId: (json['activityId'] is int)
          ? json['activityId'] as int
          : int.tryParse(json['activityId'].toString()) ?? 0,
      activityName: json['activityName']?.toString() ?? '',
      category: (json['category']?.toString() ?? 'ADL').toUpperCase(),
      totalLogsInPeriod: (json['totalLogsInPeriod'] is int)
          ? json['totalLogsInPeriod'] as int
          : int.tryParse(json['totalLogsInPeriod'].toString()) ?? 0,
      lastLoggedAt: lastLoggedAt,
      noRecentActivity: json['noRecentActivity'] == true,
    );
  }
}
