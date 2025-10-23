import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A customizable speedometer / gauge widget with segments, ticks, labels, and an animated needle.
///
/// The gauge maps [min]..[max] along an arc defined by [startAngleDeg] and [sweepAngleDeg].
/// Provide colored [segments] to paint ranges (e.g., green/yellow/red).
///
/// The center shows the current [value] (rounded) and optional [units].
///
/// Example:
/// ```dart
/// SpeedometerGauge(
///   min: 0,
///   max: 240,
///   value: 90,
///   units: 'km/h',
///   segments: const [
///     GaugeSegment(to: 120, color: Colors.green),
///     GaugeSegment(to: 180, color: Colors.orange),
///     GaugeSegment(to: 240, color: Colors.red),
///   ],
/// )
/// ```
class SpeedometerGauge extends StatelessWidget {
  const SpeedometerGauge({
    super.key,
    required this.min,
    required this.max,
    required this.value,
    this.segments = const [],
    this.size = 260,
    this.startAngleDeg = 150, // typical automotive layout (~7 o'clock)
    this.sweepAngleDeg = 240, // covers ~7 o'clock to ~5 o'clock
    this.needleColor,
    this.tickColor,
    this.labelStyle,
    this.valueStyle,
    this.units,
    this.showTicks = true,
    this.majorTickCount = 7,
    this.minorTicksPerInterval = 4,
    this.duration = const Duration(milliseconds: 600),
    this.curve = Curves.easeOutCubic,
  }) : assert(max > min, 'max must be greater than min');

  /// Minimum numeric value mapped to the start of the arc.
  final double min;

  /// Maximum numeric value mapped to the end of the arc.
  final double max;

  /// Current (animated) value. Clamped between [min] and [max] for drawing.
  final double value;

  /// Colored arc segments painted beneath the ticks.
  final List<GaugeSegment> segments;

  /// Square size of the gauge (width and height).
  final double size;

  /// Start angle in degrees (0° is +X to the right; angles increase clockwise).
  final double startAngleDeg;

  /// Total sweep in degrees from [startAngleDeg].
  final double sweepAngleDeg;

  /// Color of the needle + hub.
  final Color? needleColor;

  /// Color for ticks and tick labels.
  final Color? tickColor;

  /// Text style for tick labels.
  final TextStyle? labelStyle;

  /// Text style for the center value text.
  final TextStyle? valueStyle;

  /// Optional units text shown below the center value (e.g., "km/h").
  final String? units;

  /// Whether to draw major/minor ticks and labels.
  final bool showTicks;

  /// Number of labeled major ticks across the arc (inclusive of ends).
  final int majorTickCount;

  /// Number of minor ticks between two major ticks.
  final int minorTicksPerInterval;

  /// Animation duration when [value] changes.
  final Duration duration;

  /// Animation curve when [value] changes.
  final Curve curve;

  double _valueToT(double v) => ((v - min) / (max - min)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final t = _valueToT(value);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: t),
      duration: duration,
      curve: curve,
      builder: (context, animatedT, _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _SpeedometerPainter(
              min: min,
              max: max,
              t: animatedT,
              segments: segments,
              startAngle: _deg2rad(startAngleDeg),
              sweepAngle: _deg2rad(sweepAngleDeg),
              needleColor: needleColor ?? Theme.of(context).colorScheme.primary,
              tickColor: tickColor ?? Theme.of(context).colorScheme.outline,
              labelStyle: labelStyle ??
                  Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.8),
                  ),
              showTicks: showTicks,
              majorTickCount: majorTickCount,
              minorTicksPerInterval: minorTicksPerInterval,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 130,
                  ),
                  Text(
                    value.toStringAsFixed(0),
                    style: valueStyle ??
                        Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (units != null)
                    Text(
                      units!,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).hintColor,fontSize: 15
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Describes a colored arc range painted beneath ticks.
///
/// Create multiple segments to represent low/medium/high zones.
/// Each segment starts from the previous segment's end (or [SpeedometerGauge.min])
/// and extends up to [to].
class GaugeSegment {
  /// Draws from the previous segment end (or min) up to this [to] value.
  const GaugeSegment({required this.to, required this.color, this.thickness});

  /// Segment end value (inclusive) in the same units as the gauge [value].
  final double to;

  /// Arc color for this range.
  final Color color;

  /// Optional per-segment thickness (stroke width).
  final double? thickness; // optional per-segment thickness
}

class _SpeedometerPainter extends CustomPainter {
  _SpeedometerPainter({
    required this.min,
    required this.max,
    required this.t,
    required this.segments,
    required this.startAngle,
    required this.sweepAngle,
    required this.needleColor,
    required this.tickColor,
    required this.labelStyle,
    required this.showTicks,
    required this.majorTickCount,
    required this.minorTicksPerInterval,
  });

  final double min;
  final double max;

  /// Normalized 0..1 position of the needle across the arc.
  final double t;

  final List<GaugeSegment> segments;
  final double startAngle;
  final double sweepAngle;

  final Color needleColor;
  final Color tickColor;
  final TextStyle? labelStyle;

  final bool showTicks;
  final int majorTickCount;
  final int minorTicksPerInterval;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.44;

    _drawSegments(canvas, center, radius);
    if (showTicks) _drawTicks(canvas, center, radius);
    _drawNeedle(canvas, center, radius);
  }

  void _drawSegments(Canvas canvas, Offset c, double r) {
    var last = min;
    for (final seg in segments) {
      final fromT = ((last - min) / (max - min)).clamp(0.0, 1.0);
      final toT = ((seg.to - min) / (max - min)).clamp(0.0, 1.0);
      final fromA = startAngle + sweepAngle * fromT;
      final toA = startAngle + sweepAngle * toT;

      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = seg.thickness ?? math.max(6.0, r * 0.06)
        ..strokeCap = StrokeCap.round;

      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawArc(rect, fromA, (toA - fromA), false, paint);
      last = seg.to;
    }
  }

  void _drawTicks(Canvas canvas, Offset c, double r) {
    final majorLen = r * 0.14;
    final minorLen = r * 0.08;

    final majorPaint = Paint()
      ..color = tickColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final minorPaint = Paint()
      ..color = tickColor.withOpacity(0.7)
      ..strokeWidth = 1;

    final totalIntervals = (majorTickCount - 1).clamp(1, 100);
    for (int i = 0; i <= totalIntervals; i++) {
      final frac = i / totalIntervals;
      final ang = startAngle + sweepAngle * frac;
      final p1 = _pointOnCircle(c, r * 0.92, ang);
      final p2 = _pointOnCircle(c, r * 0.92 - majorLen, ang);
      canvas.drawLine(p1, p2, majorPaint);

      // Label
      final labelVal = (min + (max - min) * frac).round();
      final tp = _pointOnCircle(c, r * 0.92 - majorLen - 10, ang);
      _drawText(canvas, Offset(tp.dx, tp.dy), '$labelVal');

      // Minor ticks between majors
      if (i < totalIntervals && minorTicksPerInterval > 0) {
        for (int m = 1; m <= minorTicksPerInterval; m++) {
          final subFrac =
              (i + m / (minorTicksPerInterval + 1)) / totalIntervals;
          final subAng = startAngle + sweepAngle * subFrac;
          final sp1 = _pointOnCircle(c, r * 0.92, subAng);
          final sp2 = _pointOnCircle(c, r * 0.92 - minorLen, subAng);
          canvas.drawLine(sp1, sp2, minorPaint);
        }
      }
    }
  }

  void _drawNeedle(Canvas canvas, Offset c, double r) {
    final angle = startAngle + sweepAngle * t;
    final shaftLen = r * 0.80;
    final tailLen = r * 0.18;

    final pTip = _pointOnCircle(c, shaftLen, angle);
    final pTail = _pointOnCircle(c, -tailLen, angle);

    final needlePaint = Paint()
      ..color = needleColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(pTail, pTip, needlePaint);

    // Hub
    final hub = Paint()..color = needleColor;
    final hubRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white;
    canvas.drawCircle(c, r * 0.06, hubRing);
    canvas.drawCircle(c, r * 0.05, hub);
  }

  @override
  bool shouldRepaint(covariant _SpeedometerPainter old) {
    return t != old.t ||
        min != old.min ||
        max != old.max ||
        startAngle != old.startAngle ||
        sweepAngle != old.sweepAngle ||
        needleColor != old.needleColor ||
        tickColor != old.tickColor ||
        majorTickCount != old.majorTickCount ||
        minorTicksPerInterval != old.minorTicksPerInterval ||
        segments.length != old.segments.length ||
        !_listEquals(segments, old.segments);
  }

  bool _listEquals(List<GaugeSegment> a, List<GaugeSegment> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].to != b[i].to || a[i].color != b[i].color) return false;
    }
    return true;
  }

  Offset _pointOnCircle(Offset c, double r, double angle) =>
      Offset(c.dx + r * math.cos(angle), c.dy + r * math.sin(angle));

  void _drawText(Canvas canvas, Offset center, String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    final offset = Offset(-painter.width / 2, -painter.height / 2);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    painter.paint(canvas, offset); // keep labels upright (no rotation)
    canvas.restore();
  }
}

double _deg2rad(double d) => d * math.pi / 180;
