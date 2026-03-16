import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/models/calendar_event.dart';

class WebParityClockPainter extends CustomPainter {
  WebParityClockPainter({
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
  bool shouldRepaint(covariant WebParityClockPainter oldDelegate) {
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
