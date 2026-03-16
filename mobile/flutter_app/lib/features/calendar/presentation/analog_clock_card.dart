import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/localization/app_i18n.dart';
import '../domain/models/calendar_event.dart';
import '../domain/models/widget_snapshot.dart';

class AnalogClockCard extends StatefulWidget {
  const AnalogClockCard({
    super.key,
    required this.snapshot,
    required this.loadSource,
    required this.onRefresh,
    required this.selectedDate,
    required this.isTodaySelected,
    required this.onPreviousDate,
    required this.onNextDate,
    required this.onResetToday,
    required this.isLoading,
    required this.enableEventDetailBottomSheet,
  });

  final WidgetSnapshot snapshot;
  final String loadSource;
  final VoidCallback onRefresh;
  final DateTime selectedDate;
  final bool isTodaySelected;
  final VoidCallback onPreviousDate;
  final VoidCallback onNextDate;
  final VoidCallback onResetToday;
  final bool isLoading;
  final bool enableEventDetailBottomSheet;

  @override
  State<AnalogClockCard> createState() => _AnalogClockCardState();
}

class _AnalogClockCardState extends State<AnalogClockCard>
    with SingleTickerProviderStateMixin {
  _HoverInfo? _hoverInfo;
  late final AnimationController _clockFrameController;

  @override
  void initState() {
    super.initState();
    _clockFrameController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _clockFrameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final opacity = widget.snapshot.style.clockOpacity.clamp(0.0, 1.0);

    return Card(
      margin: EdgeInsets.zero,
      color: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: Theme.of(context).brightness == Brightness.dark
                ? const [Color(0xA00D111C), Color(0x70121826)]
                : const [Color(0xCCFFFFFF), Color(0xB3F8FAFC)],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'SMART ANALOG',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 2.4,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3B82F6),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: i18n.refreshClockSnapshotTooltip,
                  onPressed: widget.isLoading ? null : widget.onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton(
                  onPressed: widget.isLoading ? null : widget.onPreviousDate,
                  icon: const Icon(Icons.chevron_left),
                  tooltip: i18n.previousDateTooltip,
                ),
                IconButton(
                  onPressed: widget.isLoading ? null : widget.onNextDate,
                  icon: const Icon(Icons.chevron_right),
                  tooltip: i18n.nextDateTooltip,
                ),
                const SizedBox(width: 4),
                OutlinedButton(
                  onPressed: widget.isTodaySelected
                      ? null
                      : (widget.isLoading ? null : widget.onResetToday),
                  child: Text(i18n.todayButton),
                ),
                const Spacer(),
                if (widget.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                AnimatedBuilder(
                  animation: _clockFrameController,
                  builder: (context, _) {
                    return Text(
                      _formatClockNow(DateTime.now()),
                      style: Theme.of(context).textTheme.titleSmall,
                    );
                  },
                ),
              ],
            ),
            Text(
              '${_formatCalendarLabel(widget.selectedDate, i18n)} · ${widget.snapshot.timezone}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              i18n.sourceSummary(widget.loadSource),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Opacity(
              opacity: opacity,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final size = math.min(width, 580.0);
                  return Center(
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: Stack(
                        children: [
                          MouseRegion(
                            onHover: (event) {
                              final pointerNow = DateTime.now();
                              _handlePointer(
                                localOffset: event.localPosition,
                                canvasSize: Size(size, size),
                                now: pointerNow,
                                hidePastEvents: _isSameDateOnly(
                                  widget.selectedDate,
                                  pointerNow,
                                ),
                              );
                            },
                            onExit: (_) => setState(() => _hoverInfo = null),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (details) {
                                final pointerNow = DateTime.now();
                                _handleTap(
                                  localOffset: details.localPosition,
                                  canvasSize: Size(size, size),
                                  now: pointerNow,
                                  hidePastEvents: _isSameDateOnly(
                                    widget.selectedDate,
                                    pointerNow,
                                  ),
                                );
                              },
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  size: Size(size, size),
                                  painter: _WebParityClockPainter(
                                    selectedDate: widget.selectedDate,
                                    events: widget.snapshot.events,
                                    theme: widget.snapshot.style.theme,
                                    eventOpacityByte: _eventOpacityByte(
                                      widget.snapshot.style.eventOpacity,
                                    ),
                                    showSecondHand: true,
                                    repaint: _clockFrameController,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_hoverInfo != null)
                            _EventTooltip(
                              size: size,
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
          ],
        ),
      ),
    );
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
      events: widget.snapshot.events,
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
      events: widget.snapshot.events,
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

  _HoverInfo? _findHoveredEvent({
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
    return _HoverInfo(event: hovered, localOffset: localOffset);
  }

  void _showEventDetailSheet(CalendarEvent event) {
    final theme = Theme.of(context);
    final i18n = context.i18n;
    final timeSummary = _EventTooltip._formatEventRange(
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
                        color: _EventTooltip._parseColor(
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

  int _eventOpacityByte(double value) {
    final normalized = value <= 1.0 ? value.clamp(0.0, 1.0) : (value / 100.0);
    return (normalized * 255).round().clamp(0, 255);
  }

  String _formatClockNow(DateTime now) {
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  String _formatCalendarLabel(DateTime value, AppI18n i18n) {
    final dateLabel =
        '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    return '$dateLabel (${i18n.weekdayAbbreviation(value.weekday)})';
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
}

class _HoverInfo {
  const _HoverInfo({required this.event, required this.localOffset});

  final CalendarEvent event;
  final Offset localOffset;
}

class _EventTooltip extends StatelessWidget {
  const _EventTooltip({
    required this.size,
    required this.hoverInfo,
    required this.allDayLabel,
  });

  final double size;
  final _HoverInfo hoverInfo;
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
                      color: _parseColor(
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
                _formatEventRange(event, allDayLabel),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatEventRange(CalendarEvent event, String allDayLabel) {
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

  static Color _parseColor(String value, Color fallback) {
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

class _WebPalette {
  const _WebPalette({
    required this.face,
    required this.border,
    required this.tick,
    required this.hand,
    required this.number,
    required this.second,
  });

  final Color face;
  final Color border;
  final Color tick;
  final Color hand;
  final Color number;
  final Color second;
}

class _WebParityClockPainter extends CustomPainter {
  _WebParityClockPainter({
    required this.selectedDate,
    required this.events,
    required this.theme,
    required this.eventOpacityByte,
    required this.showSecondHand,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final DateTime selectedDate;
  final List<CalendarEvent> events;
  final String theme;
  final int eventOpacityByte;
  final bool showSecondHand;

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();
    final hidePastEvents = _isSameDateOnly(selectedDate, now);
    final palette = theme == 'light'
        ? const _WebPalette(
            face: Color.fromRGBO(255, 255, 255, 0.6),
            border: Color.fromRGBO(148, 163, 184, 0.3),
            tick: Color(0xFF334155),
            hand: Color(0xFF0F172A),
            number: Color(0xFF0F172A),
            second: Color(0xFFDC2626),
          )
        : const _WebPalette(
            face: Color.fromRGBO(18, 24, 38, 0.4),
            border: Color.fromRGBO(143, 166, 214, 0.2),
            tick: Color(0xFFCBD5E1),
            hand: Color(0xFFF8FAFC),
            number: Color(0xFFF8FAFC),
            second: Color(0xFFEF4444),
          );

    final shortest = math.min(size.width, size.height);
    final scale = (shortest - 12) / 200;
    final center = Offset(size.width / 2, size.height / 2);
    final faceRadius = 95 * scale;
    final pieRadius = 88 * scale;
    final arcRadius = 94 * scale;

    final faceFill = Paint()
      ..color = palette.face
      ..style = PaintingStyle.fill;
    final faceBorder = Paint()
      ..color = palette.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, faceRadius, faceFill);
    canvas.drawCircle(center, faceRadius, faceBorder);

    final currentIsAm = now.hour < 12;
    final allDayEvents = events.where((event) => event.allDay).toList();
    for (var index = 0; index < allDayEvents.length; index += 1) {
      final event = allDayEvents[index];
      final spacing = 10 * scale;
      final totalWidth = (allDayEvents.length - 1) * spacing;
      final dotX = center.dx + (-totalWidth / 2) + index * spacing;
      final dotY = center.dy + (-103 * scale);
      final alpha = (eventOpacityByte / 255).clamp(0.1, 1.0);
      final dotPaint = Paint()
        ..color = _withOpacity(
          _parseColor(event.colorHex, const Color(0xFF64748B)),
          alpha,
        )
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(dotX, dotY), 3.5 * scale, dotPaint);
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

      var startHour = (evStart.hour % 12) + (evStart.minute / 60);
      var startAngle = 90 - startHour * 30;
      var spanAngle =
          -((math.min(12 * 60, _minutesBetween(evStart, evEnd)) / (12 * 60)) *
              360);

      if (isInProgress) {
        startHour = (now.hour % 12) + now.minute / 60 + now.second / 3600;
        startAngle = 90 - startHour * 30;
        final remainingHours =
            ((evEnd.millisecondsSinceEpoch - now.millisecondsSinceEpoch) /
                    3600000)
                .clamp(0, 12)
                .toDouble();
        spanAngle = -(remainingHours * 30);
      }

      final startRad = -_degToRad(startAngle);
      final endRad = -_degToRad(startAngle + spanAngle);
      final sweepRad = endRad - startRad;
      final eventColor = _parseColor(event.colorHex, const Color(0xFF64748B));
      final alphaBase = (eventOpacityByte / 255).clamp(0.15, 1.0);

      if (sweepRad.abs() < 0.0001) {
        _drawZeroDurationMarker(
          canvas: canvas,
          center: center,
          angleRad: startRad,
          isCurrentCycle: isCurrentCycle,
          pieRadius: pieRadius,
          arcRadius: arcRadius,
          scale: scale,
          color: _withOpacity(
            eventColor,
            isCurrentCycle
                ? (isInProgress ? alphaBase : alphaBase * 0.7)
                : alphaBase * 0.8,
          ),
        );
        continue;
      }

      if (isCurrentCycle) {
        final path = Path()
          ..moveTo(center.dx, center.dy)
          ..arcTo(
            Rect.fromCircle(center: center, radius: pieRadius),
            startRad,
            sweepRad,
            false,
          )
          ..close();

        final fillPaint = Paint()
          ..color = _withOpacity(
            eventColor,
            isInProgress ? alphaBase : alphaBase * 0.45,
          )
          ..style = PaintingStyle.fill;
        canvas.drawPath(path, fillPaint);

        final strokePaint = Paint()
          ..color = eventColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: pieRadius),
          startRad,
          sweepRad,
          false,
          strokePaint,
        );
      } else {
        final arcPaint = Paint()
          ..color = _withOpacity(eventColor, alphaBase * 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: arcRadius),
          startRad,
          sweepRad,
          false,
          arcPaint,
        );
      }
    }

    final majorTickPaint = Paint()
      ..color = palette.tick
      ..strokeWidth = 2;
    final minorTickPaint = Paint()
      ..color = palette.tick
      ..strokeWidth = 1;
    for (var index = 0; index < 12; index += 1) {
      final angle = (index * math.pi) / 6;
      final start =
          center + Offset(math.cos(angle), math.sin(angle)) * (85 * scale);
      final end =
          center + Offset(math.cos(angle), math.sin(angle)) * (90 * scale);
      canvas.drawLine(start, end, majorTickPaint);
    }
    for (var index = 0; index < 48; index += 1) {
      if (index % 4 == 0) {
        continue;
      }
      final angle = (index * math.pi) / 24;
      final start =
          center + Offset(math.cos(angle), math.sin(angle)) * (88 * scale);
      final end =
          center + Offset(math.cos(angle), math.sin(angle)) * (90 * scale);
      canvas.drawLine(start, end, minorTickPaint);
    }

    final hourValue = (now.hour % 12) + now.minute / 60;
    final minuteValue = now.minute + now.second / 60;
    final secondValue = now.second + now.millisecond / 1000;

    _drawTriangleHand(
      canvas: canvas,
      center: center,
      angle: (hourValue * math.pi) / 6,
      leftX: -4 * scale,
      baseY: 8 * scale,
      rightX: 4 * scale,
      tipY: -50 * scale,
      color: palette.hand,
    );
    _drawTriangleHand(
      canvas: canvas,
      center: center,
      angle: (minuteValue * math.pi) / 30,
      leftX: -3 * scale,
      baseY: 8 * scale,
      rightX: 3 * scale,
      tipY: -75 * scale,
      color: palette.hand,
    );
    if (showSecondHand) {
      _drawTriangleHand(
        canvas: canvas,
        center: center,
        angle: (secondValue * math.pi) / 30,
        leftX: -1 * scale,
        baseY: 15 * scale,
        rightX: 1 * scale,
        tipY: -85 * scale,
        color: palette.second,
      );
    }

    canvas.drawCircle(center, 3 * scale, Paint()..color = palette.hand);

    final textStyle = TextStyle(
      color: palette.number,
      fontSize: (9 * scale).roundToDouble(),
      fontWeight: FontWeight.w500,
    );
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (var hour = 1; hour <= 12; hour += 1) {
      final angle = _degToRad((hour * 30) + 270);
      final x = center.dx + (72 * scale * math.cos(angle));
      final y = center.dy + (72 * scale * math.sin(angle));
      textPainter.text = TextSpan(text: '$hour', style: textStyle);
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }
  }

  void _drawTriangleHand({
    required Canvas canvas,
    required Offset center,
    required double angle,
    required double leftX,
    required double baseY,
    required double rightX,
    required double tipY,
    required Color color,
  }) {
    final path = Path()
      ..moveTo(leftX, baseY)
      ..lineTo(rightX, baseY)
      ..lineTo(0, tipY)
      ..close();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  void _drawZeroDurationMarker({
    required Canvas canvas,
    required Offset center,
    required double angleRad,
    required bool isCurrentCycle,
    required double pieRadius,
    required double arcRadius,
    required double scale,
    required Color color,
  }) {
    final radial = Offset(math.cos(angleRad), math.sin(angleRad));
    final innerRadius = isCurrentCycle ? 8 * scale : arcRadius - (6 * scale);
    final outerRadius = isCurrentCycle ? pieRadius : arcRadius + (6 * scale);
    final markerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = isCurrentCycle ? 2.6 * scale : 3.2 * scale
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center + radial * innerRadius,
      center + radial * outerRadius,
      markerPaint,
    );
  }

  double _minutesBetween(DateTime start, DateTime end) {
    return math.max(
      0,
      (end.millisecondsSinceEpoch - start.millisecondsSinceEpoch) / 60000,
    );
  }

  double _degToRad(double value) => value * (math.pi / 180);

  Color _parseColor(String value, Color fallback) {
    final cleaned = value.trim().replaceFirst('#', '');
    if (cleaned.length == 6) {
      final parsed = int.tryParse(cleaned, radix: 16);
      if (parsed != null) {
        return Color(0xFF000000 | parsed);
      }
    }
    return fallback;
  }

  Color _withOpacity(Color color, double opacity) {
    final clamped = opacity.clamp(0.0, 1.0);
    return color.withValues(alpha: clamped);
  }

  @override
  bool shouldRepaint(covariant _WebParityClockPainter oldDelegate) {
    return oldDelegate.theme != theme ||
        oldDelegate.selectedDate != selectedDate ||
        oldDelegate.eventOpacityByte != eventOpacityByte ||
        oldDelegate.showSecondHand != showSecondHand ||
        oldDelegate.events != events;
  }

  bool _isSameDateOnly(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}
