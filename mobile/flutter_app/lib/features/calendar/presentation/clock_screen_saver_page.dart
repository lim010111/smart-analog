import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/localization/app_i18n.dart';
import '../../../integrations/widget_host/widget_host_bridge.dart';
import '../domain/models/calendar_event.dart';
import '../domain/models/widget_snapshot.dart';
import 'web_parity_clock_painter.dart';

typedef ScreenSaverReloadSnapshot = Future<WidgetSnapshot> Function();
typedef ScreenSaverLoadSource = String Function();

class ClockScreenSaverPage extends StatefulWidget {
  const ClockScreenSaverPage({
    super.key,
    required this.initialSnapshot,
    required this.reloadSnapshot,
    required this.currentLoadSource,
    required this.showBottomInfoPanel,
    required this.enableEventDetailBottomSheet,
  });

  final WidgetSnapshot initialSnapshot;
  final ScreenSaverReloadSnapshot reloadSnapshot;
  final ScreenSaverLoadSource currentLoadSource;
  final bool showBottomInfoPanel;
  final bool enableEventDetailBottomSheet;

  @override
  State<ClockScreenSaverPage> createState() => _ClockScreenSaverPageState();
}

class _ClockScreenSaverPageState extends State<ClockScreenSaverPage>
    with SingleTickerProviderStateMixin {
  final WidgetHostBridge _widgetHostBridge = WidgetHostBridge();
  late WidgetSnapshot _snapshot;
  late AnimationController _clockFrameController;
  Timer? _autoRefreshTimer;
  bool _loading = false;
  late String _loadSource;
  _ScreenSaverHoverInfo? _hoverInfo;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initialSnapshot;
    _loadSource = widget.currentLoadSource();
    _clockFrameController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
    unawaited(_enterScreenSaverMode());
    unawaited(_refreshSnapshot(silent: true));
    _autoRefreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) {
        unawaited(_refreshSnapshot(silent: true));
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _clockFrameController.dispose();
    unawaited(_leaveScreenSaverMode());
    super.dispose();
  }

  Future<void> _enterScreenSaverMode() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await _widgetHostBridge.enableScreenSaverMode();
  }

  Future<void> _leaveScreenSaverMode() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await _widgetHostBridge.disableScreenSaverMode();
  }

  Future<void> _refreshSnapshot({required bool silent}) async {
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
    });

    final i18n = context.i18n;
    try {
      final next = await widget.reloadSnapshot();
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = next;
        _loadSource = widget.currentLoadSource();
      });
    } catch (error) {
      if (!mounted || silent) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(i18n.refreshFailed('$error'))));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  int _eventOpacityByte(double value) {
    final normalized = value <= 1.0 ? value.clamp(0.0, 1.0) : (value / 100.0);
    return (normalized * 255).round().clamp(0, 255);
  }

  String _formatNow(DateTime now) {
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  String _formatDate(DateTime value, AppI18n i18n) {
    final yyyy = value.year.toString().padLeft(4, '0');
    final mm = value.month.toString().padLeft(2, '0');
    final dd = value.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd (${i18n.weekdayAbbreviation(value.weekday)})';
  }

  String _formatEventLine(AppI18n i18n, CalendarEvent event) {
    if (event.allDay) {
      return '${i18n.allDayLabel} - ${event.title}';
    }
    final start =
        '${event.startTime.hour.toString().padLeft(2, '0')}:${event.startTime.minute.toString().padLeft(2, '0')}';
    final end =
        '${event.endTime.hour.toString().padLeft(2, '0')}:${event.endTime.minute.toString().padLeft(2, '0')}';
    final timePart = start == end ? start : '$start-$end';
    return '$timePart - ${event.title}';
  }

  Color _parseHexColor(String value) {
    final cleaned = value.trim().replaceFirst('#', '');
    final parsed = int.tryParse(cleaned, radix: 16);
    if (parsed == null || cleaned.length != 6) {
      return const Color(0xFF64748B);
    }
    return Color(0xFF000000 | parsed);
  }

  void _handlePointer({
    required Offset localOffset,
    required Size canvasSize,
    required DateTime now,
    required bool hidePastEvents,
  }) {
    final match = _findHoveredEvent(
      localOffset: localOffset,
      canvasSize: canvasSize,
      now: now,
      events: _snapshot.events,
      hidePastEvents: hidePastEvents,
    );
    setState(() {
      _hoverInfo = match;
    });
  }

  void _handleTap({
    required Offset localOffset,
    required Size canvasSize,
    required DateTime now,
    required bool hidePastEvents,
  }) {
    final match = _findHoveredEvent(
      localOffset: localOffset,
      canvasSize: canvasSize,
      now: now,
      events: _snapshot.events,
      hidePastEvents: hidePastEvents,
    );
    if (match == null) {
      setState(() {
        _hoverInfo = null;
      });
      return;
    }

    setState(() {
      _hoverInfo = match;
    });
    if (!widget.enableEventDetailBottomSheet) {
      return;
    }
    _showEventDetailSheet(match.event);
  }

  _ScreenSaverHoverInfo? _findHoveredEvent({
    required Offset localOffset,
    required Size canvasSize,
    required DateTime now,
    required List<CalendarEvent> events,
    required bool hidePastEvents,
  }) {
    final scale = (canvasSize.width - 12) / 200;
    final pieRadius = 88 * scale;
    final arcRadius = 94 * scale;
    final arcHitTolerance = math.max(4.0, 1.8 * scale);
    final wedgeOuterPadding = math.max(2.0, 1.2 * scale);

    final centerX = canvasSize.width / 2;
    final centerY = canvasSize.height / 2;
    final x = localOffset.dx - centerX;
    final y = localOffset.dy - centerY;
    final distance = math.sqrt(x * x + y * y);
    final currentIsAm = now.hour < 12;
    final allDayEvents = events.where((event) => event.allDay).toList();
    final allDaySpacing = 10 * scale;
    final allDayTotalWidth = (allDayEvents.length - 1) * allDaySpacing;
    final allDayHitRadius = math.max(8.0, 8 * scale);

    CalendarEvent? hovered;
    var bestScore = double.infinity;

    for (var index = 0; index < allDayEvents.length; index += 1) {
      final event = allDayEvents[index];
      final dotX = centerX + (-allDayTotalWidth / 2) + index * allDaySpacing;
      final dotY = centerY + (-103 * scale);
      final dotDistance = (localOffset - Offset(dotX, dotY)).distance;
      if (dotDistance > allDayHitRadius) {
        continue;
      }

      final score = dotDistance / allDayHitRadius;
      if (score < bestScore) {
        bestScore = score;
        hovered = event;
      }
    }

    for (final event in events) {
      if (event.allDay) {
        continue;
      }
      final evStart = event.startTime;
      final evEnd = event.endTime;
      if (hidePastEvents && now.isAfter(evEnd)) {
        continue;
      }

      final isInProgress =
          (now.isAfter(evStart) || now.isAtSameMomentAs(evStart)) &&
          (now.isBefore(evEnd) || now.isAtSameMomentAs(evEnd));
      final isCurrentCycle =
          isInProgress || (currentIsAm == (evStart.hour < 12));

      var startAngle = 90 - ((evStart.hour % 12) + evStart.minute / 60) * 30;
      var spanAngle =
          -((math.min(12 * 60, _minutesBetween(evStart, evEnd)) / (12 * 60)) *
              360);
      if (isInProgress) {
        startAngle =
            90 - ((now.hour % 12) + now.minute / 60 + now.second / 3600) * 30;
        final remainingHours =
            ((evEnd.millisecondsSinceEpoch - now.millisecondsSinceEpoch) /
                    3600000)
                .clamp(0, 12)
                .toDouble();
        spanAngle = -(remainingHours * 30);
      }

      final pointAngle = math.atan2(-y, x) * 180 / math.pi;
      final absSpan = spanAngle.abs();
      double score;

      if (absSpan <= 0) {
        final markerRad = -(startAngle * (math.pi / 180));
        final unitX = math.cos(markerRad);
        final unitY = math.sin(markerRad);
        final innerRadius = isCurrentCycle
            ? 8 * scale
            : arcRadius - (6 * scale);
        final outerRadius = isCurrentCycle
            ? pieRadius
            : arcRadius + (6 * scale);
        final projection = x * unitX + y * unitY;
        final perpendicular = (x * unitY - y * unitX).abs();
        final markerHitTolerance = math.max(4.0, 2.6 * scale);

        if (projection < innerRadius - markerHitTolerance ||
            projection > outerRadius + markerHitTolerance ||
            perpendicular > markerHitTolerance) {
          continue;
        }

        final markerLength = math.max(1.0, outerRadius - innerRadius);
        final markerCenter = (innerRadius + outerRadius) / 2;
        final alongScore = (projection - markerCenter).abs() / markerLength;
        final crossScore = perpendicular / markerHitTolerance;
        score = crossScore * 2 + alongScore;
        if (!isCurrentCycle) {
          score += 0.8;
        }
      } else {
        var diff = startAngle - pointAngle;
        while (diff < 0) {
          diff += 360;
        }
        while (diff >= 360) {
          diff -= 360;
        }

        if (diff > absSpan) {
          continue;
        }

        final angularScore = diff / absSpan;
        if (isCurrentCycle) {
          final wedgeMaxRadius = pieRadius + wedgeOuterPadding;
          if (distance > wedgeMaxRadius) {
            continue;
          }

          final edgeDistanceScore = (pieRadius - distance).abs() / pieRadius;
          score = angularScore * 2 + edgeDistanceScore * 2;
          if ((distance - arcRadius).abs() <= arcHitTolerance) {
            score += 1.5;
          }
          if (hidePastEvents) {
            score -= 1.0;
          }
        } else {
          final radialDiff = (distance - arcRadius).abs();
          if (radialDiff > arcHitTolerance) {
            continue;
          }

          score = angularScore * 2 + radialDiff * 4;
          if (hidePastEvents) {
            score += 2.0;
          }
        }
      }

      if (score < bestScore) {
        bestScore = score;
        hovered = event;
      }
    }

    if (hovered == null) {
      return null;
    }
    return _ScreenSaverHoverInfo(event: hovered, localOffset: localOffset);
  }

  void _showEventDetailSheet(CalendarEvent event) {
    final theme = Theme.of(context);
    final i18n = context.i18n;
    final timeSummary = _ScreenSaverEventTooltip.formatEventRange(
      event,
      i18n.allDayLabel,
    );
    final startedAt = _formatDateTime(event.startTime);
    final endedAt = _formatDateTime(event.endTime);
    final description = event.description.trim();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _ScreenSaverEventTooltip.parseColor(
                          event.colorHex,
                          const Color(0xFF64748B),
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        event.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(timeSummary, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text('$startedAt ~ $endedAt', style: theme.textTheme.bodySmall),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(description, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDateTime(DateTime value) {
    final yyyy = value.year.toString().padLeft(4, '0');
    final mm = value.month.toString().padLeft(2, '0');
    final dd = value.day.toString().padLeft(2, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd $hh:$min';
  }

  bool _isSameDateOnly(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  double _minutesBetween(DateTime start, DateTime end) {
    return math.max(
      0,
      (end.millisecondsSinceEpoch - start.millisecondsSinceEpoch) / 60000,
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final previewEvents = _snapshot.events.take(4).toList();
    final headerColor = _snapshot.style.theme == 'light'
        ? const Color(0xFF0F172A)
        : const Color(0xFFF8FAFC);
    final subTextColor = _snapshot.style.theme == 'light'
        ? const Color(0xFF334155)
        : const Color(0xFF94A3B8);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.15),
                  radius: 1.05,
                  colors: [Color(0xFF0B1220), Color(0xFF020617)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                if (widget.showBottomInfoPanel)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 12, 0),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                          color: headerColor,
                          tooltip: i18n.screenSaverExitLabel,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                i18n.screenSaverTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: headerColor,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Text(
                                _formatDate(_snapshot.generatedAt, i18n),
                                style: TextStyle(color: subTextColor),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _loading
                              ? null
                              : () =>
                                    unawaited(_refreshSnapshot(silent: false)),
                          icon: _loading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                          color: headerColor,
                          tooltip: i18n.refreshClockSnapshotTooltip,
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final shortest = math.min(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      final clockSize = shortest.clamp(260.0, 560.0);
                      return Center(
                        child: SizedBox(
                          width: clockSize,
                          height: clockSize,
                          child: Stack(
                            children: [
                              MouseRegion(
                                onHover: (event) {
                                  final pointerNow = DateTime.now();
                                  _handlePointer(
                                    localOffset: event.localPosition,
                                    canvasSize: Size(clockSize, clockSize),
                                    now: pointerNow,
                                    hidePastEvents: _isSameDateOnly(
                                      _snapshot.generatedAt,
                                      pointerNow,
                                    ),
                                  );
                                },
                                onExit: (_) =>
                                    setState(() => _hoverInfo = null),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapDown: (details) {
                                    final pointerNow = DateTime.now();
                                    _handleTap(
                                      localOffset: details.localPosition,
                                      canvasSize: Size(clockSize, clockSize),
                                      now: pointerNow,
                                      hidePastEvents: _isSameDateOnly(
                                        _snapshot.generatedAt,
                                        pointerNow,
                                      ),
                                    );
                                  },
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      size: Size(clockSize, clockSize),
                                      painter: WebParityClockPainter(
                                        selectedDate: _snapshot.generatedAt,
                                        events: _snapshot.events,
                                        theme: _snapshot.style.theme,
                                        eventOpacityByte: _eventOpacityByte(
                                          _snapshot.style.eventOpacity,
                                        ),
                                        showSecondHand: true,
                                        repaint: _clockFrameController,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (_hoverInfo != null)
                                _ScreenSaverEventTooltip(
                                  size: clockSize,
                                  hoverInfo: _hoverInfo!,
                                  allDayLabel: i18n.allDayLabel,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (widget.showBottomInfoPanel)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                AnimatedBuilder(
                                  animation: _clockFrameController,
                                  builder: (context, _) {
                                    return Text(
                                      _formatNow(DateTime.now()),
                                      style: TextStyle(
                                        color: headerColor,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                        fontWeight: FontWeight.w700,
                                      ),
                                    );
                                  },
                                ),
                                const Spacer(),
                                Text(
                                  i18n.sourceSummary(_loadSource),
                                  style: TextStyle(color: subTextColor),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (previewEvents.isEmpty)
                              Text(
                                i18n.eventsSummary(0),
                                style: TextStyle(color: subTextColor),
                              )
                            else
                              ...previewEvents.map(
                                (event) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: _parseHexColor(event.colorHex),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _formatEventLine(i18n, event),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: headerColor),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenSaverHoverInfo {
  const _ScreenSaverHoverInfo({required this.event, required this.localOffset});

  final CalendarEvent event;
  final Offset localOffset;
}

class _ScreenSaverEventTooltip extends StatelessWidget {
  const _ScreenSaverEventTooltip({
    required this.size,
    required this.hoverInfo,
    required this.allDayLabel,
  });

  final double size;
  final _ScreenSaverHoverInfo hoverInfo;
  final String allDayLabel;

  @override
  Widget build(BuildContext context) {
    final left = (hoverInfo.localOffset.dx + 12).clamp(0.0, size - 210);
    final top = (hoverInfo.localOffset.dy + 12).clamp(0.0, size - 92);
    final event = hoverInfo.event;
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: parseColor(
                        event.colorHex,
                        const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                formatEventRange(event, allDayLabel),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String formatEventRange(CalendarEvent event, String allDayLabel) {
    if (event.allDay) {
      return allDayLabel;
    }
    final start =
        '${event.startTime.hour.toString().padLeft(2, '0')}:${event.startTime.minute.toString().padLeft(2, '0')}';
    final end =
        '${event.endTime.hour.toString().padLeft(2, '0')}:${event.endTime.minute.toString().padLeft(2, '0')}';
    if (start == end) {
      return start;
    }
    return '$start - $end';
  }

  static Color parseColor(String value, Color fallback) {
    final cleaned = value.trim().replaceFirst('#', '');
    if (cleaned.length == 6) {
      final parsed = int.tryParse(cleaned, radix: 16);
      if (parsed != null) {
        return Color(0xFF000000 | parsed);
      }
    }
    return fallback;
  }
}
