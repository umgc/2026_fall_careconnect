import 'package:flutter/material.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:care_connect_app/services/informed_delivery_service.dart';
import 'package:care_connect_app/features/usps/presentation/widgets/mail_envelope_read_aloud_button.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:care_connect_app/assets/usps_digest_mock.dart';
import 'dart:async';

/// ---- Domain models ----
class EmailMessage {
  final String id;
  final DateTime expectedAt;
  final List<String>
  imageUrls; // Inline/attachment image URLs or local file URIs
  final String? sender;
  final String? summary;

  EmailMessage({
    required this.id,
    required this.expectedAt,
    required this.imageUrls,
    this.sender,
    this.summary,
  });
}

class UspsDigest {
  final DateTime digestDate;
  final List<UspsMailpiece> mailpieces;
  final List<UspsPackage> packages;

  UspsDigest({
    required this.digestDate,
    required this.mailpieces,
    required this.packages,
  });
}

class UspsMailpiece {
  final String id;
  final String sender;
  final String summary;
  final DateTime dateIso;
  final String imageDataUrl; // data:*;base64,XXXX
  final UspsActions actions;
  Uint8List? _decoded; // lazy cache

  UspsMailpiece({
    required this.id,
    required this.sender,
    required this.summary,
    required this.dateIso,
    required this.imageDataUrl,
    required this.actions,
  });

  /// Decode the data URL to bytes (memoized).
  Uint8List? get bytes {
    _decoded ??= _decodeDataUrl(imageDataUrl);
    return _decoded;
  }
}

class UspsPackage {
  final String trackingNumber;
  final DateTime expectedDateIso;
  final UspsActions actions;

  UspsPackage({
    required this.trackingNumber,
    required this.expectedDateIso,
    required this.actions,
  });
}

class UspsActions {
  final String? track;
  final String? redelivery;
  final String? dashboard;

  UspsActions({this.track, this.redelivery, this.dashboard});
}

class MailMeta {
  final String? sender;
  final String? summary;
  const MailMeta({this.sender, this.summary});
}

/// Groups emails by the calendar day (yyyy-mm-dd) and flattens to image lists.
Map<DateTime, List<String>> groupImagesByDate(List<EmailMessage> emails) {
  final Map<String, List<String>> temp = {};
  for (final m in emails) {
    final dayKey = _dayKey(m.expectedAt);
    temp.putIfAbsent(dayKey, () => []);
    temp[dayKey]!.addAll(m.imageUrls);
  }

  // Convert back to DateTime keys at midnight for sorting & display
  final Map<DateTime, List<String>> result = {};
  temp.forEach((k, v) {
    final parts = k.split('-').map(int.parse).toList();
    result[DateTime(parts[0], parts[1], parts[2])] = v;
  });
  return result;
}

String _dayKey(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-'
    '${dt.month.toString().padLeft(2, '0')}-'
    '${dt.day.toString().padLeft(2, '0')}';

String formatDay(DateTime dt) {
  // e.g., Mon, Oct 13, 2025
  const weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const month = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final wd = weekday[(dt.weekday + 6) % 7]; // make Monday index 0
  final mo = month[dt.month - 1];
  return '$wd, $mo ${dt.day}, ${dt.year}';
}

/// ---- App ----
class InformedDeliveryScreen extends StatefulWidget {
  const InformedDeliveryScreen({super.key});

  @override
  State<InformedDeliveryScreen> createState() => _InformedDeliveryScreenState();
}

class _InformedDeliveryScreenState extends State<InformedDeliveryScreen> {
  // final enableUSPSDigest = getEnableUSPSDigest().toLowerCase() == 'true';
  // final enableMockUSPSDigest =
  //     getEnableMockUSPSDigest().toLowerCase() == 'true';

  final enableUSPSDigest = true;
  final enableMockUSPSDigest = true;

  final TextEditingController _searchCtl = TextEditingController();
  Timer? _searchDebounce;

  String _searchQuery = '';
  Map<DateTime, List<String>> _filteredImagesByDate = const {};

  bool get _isSearching => _searchQuery.trim().isNotEmpty;

  Map<DateTime, List<String>> _imagesByDate = const {};
  Map<String, MailMeta> _imageMetaByUrl = const {};

  List<DateTime> _sortedDays = const [];
  DateTime? _selectedDay;
  bool isLoadingData = false;
  int _totalMailpieces = 0;

  @override
  void initState() {
    super.initState();

    _searchCtl.addListener(() {
      final q = _searchCtl.text;
      // debounce to avoid recomputing on every keystroke
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 200), () {
        setState(() {
          _searchQuery = q;
        });
        _applySearch(); // recompute filtered map
      });
    });

    _loadDigestData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  void _applySearch() {
    if (!_isSearching) {
      // reset filtered view to original
      setState(() {
        _filteredImagesByDate = _imagesByDate;
        // keep _sortedDays / _selectedDay in sync with current map
        _syncSortedDaysAndSelected(from: _filteredImagesByDate);
      });
      return;
    }

    final q = _searchQuery.toLowerCase().trim();

    // Build filtered map
    final Map<DateTime, List<String>> filtered = {};
    _imagesByDate.forEach((day, urls) {
      final matches = <String>[];
      for (final url in urls) {
        final meta = _imageMetaByUrl[url];
        final sender = meta?.sender?.toLowerCase() ?? '';
        final summary = meta?.summary?.toLowerCase() ?? '';
        if (sender.contains(q) || summary.contains(q)) {
          matches.add(url);
        }
      }
      if (matches.isNotEmpty) {
        filtered[day] = matches;
      }
    });

    setState(() {
      _filteredImagesByDate = filtered;
      _syncSortedDaysAndSelected(from: _filteredImagesByDate);
    });
  }

  /// Keeps _sortedDays and _selectedDay consistent with whichever map is active
  void _syncSortedDaysAndSelected({required Map<DateTime, List<String>> from}) {
    final days = from.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // newest first
    _sortedDays = days;
    if (_selectedDay == null || !from.containsKey(_selectedDay)) {
      _selectedDay = days.isNotEmpty ? days.first : null;
    }
  }

  Future<UspsDigest> _fetchRealDigest() async {
    try {
      final response = await InformedDeliveryService.fetchInformedDelivery();
      final digest = parseUspsDigestResponse(response);
      return digest;
    } catch (e, st) {
      debugPrint('❌ Error fetching USPS digest: $e');
      debugPrintStack(stackTrace: st);

      // Return a fallback empty digest so the UI still works
      return UspsDigest(
        digestDate: DateTime.now(),
        mailpieces: const [],
        packages: const [],
      );
    }
  }

  Future<void> _loadDigestData() async {
    setState(() => isLoadingData = true);
    try {
      // Base digest: real if enabled, otherwise empty
      final UspsDigest base = enableUSPSDigest
          ? await _fetchRealDigest()
          : UspsDigest(
              digestDate: DateTime.now(),
              mailpieces: const [],
              packages: const [],
            );

      // Optionally apply mock data
      UspsDigest combined = base;
      if (enableMockUSPSDigest) {
        debugPrint('⚠️ Using mock mailpieces for demo purposes.');
        final mockMap = buildMockUspsDigestMap();
        final mock = parseUspsDigestResponse(mockMap);
        combined = mergeDigests(base, mock);
      }

      _hydrateDigestData(combined);
    } finally {
      if (mounted) setState(() => isLoadingData = false);
    }
  }

  void _hydrateDigestData(UspsDigest digest) {
    final inboxLike = digest.mailpieces.map((m) {
      return EmailMessage(
        id: m.id,
        expectedAt: m.dateIso,
        imageUrls: [if (m.imageDataUrl.isNotEmpty) m.imageDataUrl],
        sender: m.sender,
        summary: m.summary,
      );
    }).toList();

    _hydrateData(inboxLike);
  }

  void _hydrateData(List<EmailMessage> inbox) {
    final Map<String, List<String>> tmp = {};
    final Map<String, MailMeta> meta = {}; // collect per-image metadata

    for (final m in inbox) {
      final k = _dayKey(m.expectedAt);
      final urls = m.imageUrls;
      if (urls.isEmpty) continue;

      (tmp[k] ??= []).addAll(urls);

      // record metadata per image url
      for (final u in urls) {
        meta[u] = MailMeta(sender: m.sender, summary: m.summary);
      }
    }

    // convert day keys back to DateTime
    final Map<DateTime, List<String>> grouped = {};
    tmp.forEach((k, v) {
      final p = k.split('-').map(int.parse).toList();
      grouped[DateTime(p[0], p[1], p[2])] = v;
    });

    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    setState(() {
      _imagesByDate = grouped;
      _imageMetaByUrl = meta;
      _sortedDays = days;
      _selectedDay = days.isNotEmpty ? days.first : null;
      _totalMailpieces = inbox.length;
    });

    _applySearch();
  }

  UspsDigest parseUspsDigestResponse(Object response) {
    final Map<String, dynamic> map = switch (response) {
      final String s => _looseJsonDecode(s),
      final Map m => m.map((k, v) => MapEntry(k.toString(), v)),
      _ => throw ArgumentError(
        'Unsupported response type: ${response.runtimeType}',
      ),
    };

    DateTime parseDate(Object? v) {
      if (v is String) return DateTime.parse(v);
      throw FormatException('Invalid date value: $v');
    }

    UspsActions parseActions(Object? v) {
      final m = (v is Map)
          ? v.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
      return UspsActions(
        track: m['track']?.toString(),
        redelivery: m['redelivery']?.toString(),
        dashboard: m['dashboard']?.toString(),
      );
    }

    List<UspsMailpiece> parseMailpieces(Object? v) {
      if (v is List) {
        return v.map((e) {
          final m = (e as Map).map((k, v) => MapEntry(k.toString(), v));
          return UspsMailpiece(
            id: m['id']?.toString() ?? '',
            sender: m['sender']?.toString() ?? '',
            summary: m['summary']?.toString() ?? '',
            imageDataUrl: m['imageDataUrl']?.toString() ?? '',
            dateIso: parseDate(m['dateIso']),
            actions: parseActions(m['actions']),
          );
        }).toList();
      }
      return const [];
    }

    List<UspsPackage> parsePackages(Object? v) {
      if (v is List) {
        return v.map((e) {
          final m = (e as Map).map((k, v) => MapEntry(k.toString(), v));
          return UspsPackage(
            trackingNumber: m['trackingNumber']?.toString() ?? '',
            expectedDateIso: parseDate(m['expectedDateIso']),
            actions: parseActions(m['actions']),
          );
        }).toList();
      }
      return const [];
    }

    return UspsDigest(
      digestDate: parseDate(map['digestDate']),
      mailpieces: parseMailpieces(map['mailpieces']),
      packages: parsePackages(map['packages']),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const CommonDrawer(currentRoute: '/informed-delivery'),
      appBar: AppBarHelper.createAppBar(
        context,
        title: 'Informed Delivery ($_totalMailpieces)',
        centerTitle: true,
      ),
      body: _buildInformedDeliveryView(),
    );
  }

  Widget _buildInformedDeliveryView() {
    final Map<DateTime, List<String>> activeByDate = _isSearching
        ? _filteredImagesByDate
        : _imagesByDate;

    final hasDays = activeByDate.isNotEmpty;

    final selectedImages = _selectedDay == null
        ? const <String>[]
        : (activeByDate[_selectedDay] ?? const <String>[]);

    final visibleCount = activeByDate.values.fold<int>(
      0,
      (a, b) => a + b.length,
    );

    return Column(
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchCtl,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Search by sender or summary',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _isSearching
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtl.clear();
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Row(
            children: [
              Chip(
                label: Text(
                  _isSearching
                      ? 'Search results: $visibleCount'
                      : 'Total: $_totalMailpieces',
                ),
              ),
              const SizedBox(width: 8),
              if (_isSearching) Text("for '$_searchQuery'"),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<DateTime>(
                  initialValue: hasDays ? _selectedDay : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Select expected date',
                    border: OutlineInputBorder(),
                  ),
                  items: hasDays
                      ? _sortedDays.map((day) {
                          final count = activeByDate[day]?.length ?? 0;
                          return DropdownMenuItem<DateTime>(
                            value: day,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(formatDay(day)),
                                Text('$count item${count == 1 ? '' : 's'}'),
                              ],
                            ),
                          );
                        }).toList()
                      : const <DropdownMenuItem<DateTime>>[],
                  onChanged: hasDays
                      ? (val) => setState(() => _selectedDay = val)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: isLoadingData ? null : _onRefresh,
                icon: isLoadingData
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(isLoadingData ? 'Refreshing...' : 'Refresh'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: selectedImages.isEmpty
              ? const _EmptyState()
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.8,
                        ),
                    itemCount: selectedImages.length,
                    itemBuilder: (context, index) {
                      final url = selectedImages[index];
                      final meta = _imageMetaByUrl[url];

                      return _ImageTile(
                        url: url,
                        onTap: () => _openImageViewer(url),
                        sender: meta?.sender,
                        summary: meta?.summary,
                        senderLabel: 'Sender: ${meta?.sender}',
                        summaryLabel: 'Summary: ${meta?.summary}',
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _onRefresh() async {
    setState(() => isLoadingData = true);
    try {
      final UspsDigest base = enableUSPSDigest
          ? await _fetchRealDigest()
          : UspsDigest(
              digestDate: DateTime.now(),
              mailpieces: const [],
              packages: const [],
            );

      UspsDigest combined = base;
      if (enableMockUSPSDigest) {
        debugPrint('⚠️ Using mock mailpieces during refresh.');
        final mockMap = buildMockUspsDigestMap();
        final mock = parseUspsDigestResponse(mockMap);
        combined = mergeDigests(base, mock);
      }

      _hydrateDigestData(combined);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enableUSPSDigest
                  ? 'Mail data refreshed (API ${enableMockUSPSDigest ? "+ mock" : ""}).'
                  : 'Mail data refreshed (mock only).',
            ),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('❌ Error refreshing mail data: $e');
      debugPrintStack(stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to refresh: $e')));
      }
    } finally {
      if (mounted) setState(() => isLoadingData = false);
    }
  }

  void _openImageViewer(String url) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: InteractiveViewer(
              clipBehavior: Clip.none,
              minScale: 0.5,
              maxScale: 5,
              child: AspectRatio(
                aspectRatio: 3 / 2,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined, size: 48),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Uint8List? _decodeDataUrl(String? dataUrl) {
  if (dataUrl == null) return null;
  final i = dataUrl.indexOf(';base64,');
  if (!dataUrl.startsWith('data:') || i == -1) return null;
  final comma = dataUrl.indexOf(',', i);
  if (comma == -1) return null;
  final base64Part = dataUrl.substring(comma + 1);
  try {
    return base64Decode(base64Part);
  } catch (_) {
    return null;
  }
}

/// Some APIs (or logs) hand us "relaxed" JSON-like text (unquoted keys, single quotes).
/// This normalizer tries to coerce it to valid JSON before jsonDecode().
Map<String, dynamic> _looseJsonDecode(String s) {
  // 1) Replace single quotes around strings to double quotes (safe heuristic)
  var t = s.replaceAllMapped(
    RegExp(r"'([^']*)'"),
    (m) => '"${m.group(1)!.replaceAll(r'"', r'\"')}"',
  );

  // 2) Quote unquoted keys: {key: value} -> {"key": value}
  t = t.replaceAllMapped(
    RegExp(r'([{\s,])([A-Za-z_][A-Za-z0-9_]*)\s*:', multiLine: true),
    (m) => '${m.group(1)}"${m.group(2)}":',
  );

  // Now standard JSON
  final decoded = jsonDecode(t);
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) {
    return decoded.map((k, v) => MapEntry(k.toString(), v));
  }
  throw const FormatException('Expected a JSON object at top level.');
}

class _ImageTile extends StatelessWidget {
  final String url;
  final String? sender;
  final String? summary;
  final String? senderLabel;
  final String? summaryLabel;
  final VoidCallback onTap;
  const _ImageTile({
    required this.url,
    required this.onTap,
    this.sender,
    this.summary,
    this.senderLabel,
    this.summaryLabel,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDataUrl = url.startsWith('data:');
    Widget imageWidget;

    if (isDataUrl) {
      final bytes = _decodeDataUrl(url);
      if (bytes == null) {
        imageWidget = const Center(
          child: Icon(Icons.broken_image_outlined, size: 48),
        );
      } else if (url.startsWith('data:image/svg+xml')) {
        // SVG support (if using flutter_svg)
        imageWidget = SvgPicture.memory(bytes, fit: BoxFit.cover);
      } else {
        imageWidget = Image.memory(bytes, fit: BoxFit.cover);
      }
    } else {
      imageWidget = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Center(child: Icon(Icons.broken_image_outlined, size: 48)),
      );
    }

    final displaySender = senderLabel ?? sender;
    final displaySummary = summaryLabel ?? summary;

    return Semantics(
      label: [
        if (sender != null && sender!.trim().isNotEmpty) 'From ${sender!.trim()}',
        if (summary != null && summary!.trim().isNotEmpty) summary!.trim(),
      ].join('. '),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  InkWell(onTap: onTap, child: imageWidget),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Material(
                      color: Colors.black45,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                      ),
                      child: MailEnvelopeReadAloudButton(
                        sender: sender,
                        summary: summary,
                        iconSize: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (displaySender != null || displaySummary != null)
              Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (displaySender != null)
                      Text(
                        displaySender,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    if (displaySummary != null)
                      Text(
                        displaySummary,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_search_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 8),
          Text(
            'No mail for this expected date',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Pick another expected date from the dropdown above.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

UspsDigest mergeDigests(UspsDigest a, UspsDigest b) {
  final digestDate = (a.digestDate.isAfter(b.digestDate))
      ? a.digestDate
      : b.digestDate;

  // --- Mailpieces: dedupe by id, keep the "real" one if collision ---
  final Map<String, UspsMailpiece> byId = {
    for (final m in b.mailpieces) m.id: m, // start with mock
    for (final m in a.mailpieces) m.id: m, // overwrite with real
  };
  final mergedMail = byId.values.toList()
    ..sort((x, y) => y.dateIso.compareTo(x.dateIso)); // newest first

  // --- Packages: dedupe by trackingNumber ---
  final Map<String, UspsPackage> byTrack = {
    for (final p in b.packages) p.trackingNumber: p, // mock
    for (final p in a.packages) p.trackingNumber: p, // real overwrites
  };
  final mergedPkgs = byTrack.values.toList()
    ..sort((x, y) => y.expectedDateIso.compareTo(x.expectedDateIso));

  return UspsDigest(
    digestDate: digestDate,
    mailpieces: mergedMail,
    packages: mergedPkgs,
  );
}
