import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:care_connect_app/features/usps/domain/models/mail_image_availability.dart';

/// Renders a mailpiece envelope image, or the calm **missing-image normal
/// state** when Informed Delivery only supplies metadata.
///
/// Missing images are not errors: list/detail UIs stay usable via sender and
/// summary (Task 3.14.8).
class MailPieceImage extends StatelessWidget {
  const MailPieceImage({
    super.key,
    required this.imageRef,
    this.summary,
    this.sender,
    this.width = 48,
    this.height = 32,
    this.fit = BoxFit.cover,
    this.expanded = false,
  });

  final String? imageRef;
  final String? summary;
  final String? sender;
  final double width;
  final double height;
  final BoxFit fit;

  /// When true, show the labeled metadata-first panel (detail dialog).
  final bool expanded;

  static const Key missingNormalKey = Key('mailPieceImageMissingNormal');
  static const Key availableKey = Key('mailPieceImageAvailable');

  @override
  Widget build(BuildContext context) {
    final availability =
        MailImageClassifier.classify(imageRef, summary: summary);

    if (availability.isMissingNormalState) {
      return _MissingMailImageNormalState(
        key: missingNormalKey,
        width: width,
        height: height,
        expanded: expanded,
        sender: sender,
        summary: summary,
      );
    }

    return KeyedSubtree(
      key: availableKey,
      child: _buildImage(context, imageRef!),
    );
  }

  Widget _buildImage(BuildContext context, String imageDataUrl) {
    Widget fallback() => _MissingMailImageNormalState(
          key: missingNormalKey,
          width: width,
          height: height,
          expanded: expanded,
          sender: sender,
          summary: summary,
        );

    if (imageDataUrl.startsWith('data:')) {
      try {
        final uri = Uri.parse(imageDataUrl);
        final data = uri.data;
        if (data != null) {
          return Image.memory(
            data.contentAsBytes(),
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => fallback(),
          );
        }
      } catch (_) {
        // fall through
      }

      try {
        final base64Data = imageDataUrl.split(',').last;
        final bytes = const Base64Decoder().convert(base64Data);
        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => fallback(),
        );
      } catch (_) {
        return fallback();
      }
    }

    if (imageDataUrl.startsWith('http://') ||
        imageDataUrl.startsWith('https://')) {
      return Image.network(
        imageDataUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => fallback(),
      );
    }

    return fallback();
  }
}

/// Calm "no envelope image" panel — informational, not an error style.
class _MissingMailImageNormalState extends StatelessWidget {
  const _MissingMailImageNormalState({
    super.key,
    required this.width,
    required this.height,
    required this.expanded,
    this.sender,
    this.summary,
  });

  final double width;
  final double height;
  final bool expanded;
  final String? sender;
  final String? summary;

  static const String semanticsLabel =
      'No envelope image. Showing details from mail metadata.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconSize = (expanded ? 40.0 : height.clamp(16, 48)).toDouble();
    final usableSummary = _usableMetadata(summary);
    final usableSender = _usableMetadata(sender);

    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.55,
            ),
            borderRadius: BorderRadius.circular(expanded ? 10 : 6),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: expanded
              ? Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: width - 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.mail_outline,
                            size: iconSize,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No envelope image',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Showing details from mail metadata',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (usableSender != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              usableSender,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          if (usableSummary != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              usableSummary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                )
              : Center(
                  child: Icon(
                    Icons.mail_outline,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: iconSize,
                  ),
                ),
        ),
      ),
    );
  }

  static String? _usableMetadata(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.toLowerCase() == 'image not available') return null;
    return trimmed;
  }
}

/// Compact chip shown beside list titles when the mailpiece has no image.
class MailMetadataOnlyBadge extends StatelessWidget {
  const MailMetadataOnlyBadge({super.key});

  static const Key badgeKey = Key('mailMetadataOnlyBadge');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Details from mail metadata only',
      child: Container(
        key: badgeKey,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Metadata',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
