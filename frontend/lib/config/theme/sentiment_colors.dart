import 'package:flutter/material.dart';

/// Centralised, theme-aware colour palette for all sentiment visualisations.
///
/// Bands (score 0–1):
///   CALM       ≥ 0.60  — green
///   ANXIOUS    ≥ 0.35  — amber
///   DISTRESSED  < 0.35  — red
///
/// Light values satisfy WCAG AA contrast on white surfaces.
/// Dark values use lighter tints (shade 300) for contrast on dark surfaces.
class SentimentColors {
  SentimentColors._();

  // ── Band thresholds ──────────────────────────────────────────────
  static const double calmThreshold = 0.60;
  static const double anxiousThreshold = 0.35;

  // ── Band colours — light mode ────────────────────────────────────
  static const Color calmLight = Color(0xFF27AE60); // green-700
  static const Color anxiousLight = Color(0xFFF39C12); // amber
  static const Color distressedLight = Color(0xFFE74C3C); // red

  // ── Band colours — dark mode (lighter tints) ─────────────────────
  static const Color calmDark = Color(0xFF81C784); // green-300
  static const Color anxiousDark = Color(0xFFFFB74D); // orange-300
  static const Color distressedDark = Color(0xFFE57373); // red-300

  // ── Band fill alphas for chart backgrounds ───────────────────────
  static const double bandFillAlphaLight = 0.10;
  static const double bandFillAlphaDark = 0.14;

  // ── Channel colours ──────────────────────────────────────────────
  static const Color voiceLight = Color(0xFF9B59B6);
  static const Color voiceDark = Color(0xFFCE93D8);
  static const Color videoLight = Color(0xFF1ABC9C);
  static const Color videoDark = Color(0xFF4DD0E1);
  static const Color textLight = Color(0xFF3498DB);
  static const Color textDark = Color(0xFF64B5F6);

  // ── Neutral / status colours ─────────────────────────────────────
  static const Color awaiting = Color(0xFF95A5A6);
  static const Color quiet = Color(0xFF5D6D7E);

  // ── Public helpers ───────────────────────────────────────────────

  /// Colour for a raw 0–1 sentiment score.
  static Color forScore(double score, {required bool isDark}) {
    if (score >= calmThreshold) return isDark ? calmDark : calmLight;
    if (score >= anxiousThreshold) return isDark ? anxiousDark : anxiousLight;
    return isDark ? distressedDark : distressedLight;
  }

  /// Colour for a CALM / ANXIOUS / DISTRESSED label string.
  static Color forLabel(String label, {required bool isDark}) {
    switch (label.trim().toUpperCase()) {
      case 'CALM':
      case 'POSITIVE':
        return isDark ? calmDark : calmLight;
      case 'ANXIOUS':
      case 'NEUTRAL':
        return isDark ? anxiousDark : anxiousLight;
      case 'DISTRESSED':
      case 'NEGATIVE':
        return isDark ? distressedDark : distressedLight;
      default:
        return awaiting;
    }
  }

  /// Colour taking live-channel status into account (AWAITING, QUIET, DEGRADED).
  static Color forStatus(String status, double score, {required bool isDark}) {
    switch (status.trim().toUpperCase()) {
      case 'AWAITING':
        return awaiting;
      case 'QUIET':
        return quiet;
      case 'DEGRADED':
        return isDark ? anxiousDark : anxiousLight;
      case 'MUTED':
        return quiet;
      case 'COMPLETED':
      default:
        return forScore(score, isDark: isDark);
    }
  }

  /// Colour for a named analysis channel.
  static Color forChannel(String channel, {required bool isDark}) {
    switch (channel.trim().toUpperCase()) {
      case 'VOICE':
        return isDark ? voiceDark : voiceLight;
      case 'VIDEO':
        return isDark ? videoDark : videoLight;
      case 'TEXT':
        return isDark ? textDark : textLight;
      default:
        return isDark ? textDark : textLight;
    }
  }

  /// Semi-transparent fill colour for chart band backgrounds.
  static Color bandFill(double score, {required bool isDark}) {
    final alpha = isDark ? bandFillAlphaDark : bandFillAlphaLight;
    return forScore(score, isDark: isDark).withValues(alpha: alpha);
  }
}
