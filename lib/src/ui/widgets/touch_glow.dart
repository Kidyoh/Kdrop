import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Plays the NameDrop-style "phones touched" animation over the whole app: a
/// bloom of light at the top edge (where the other phone is) followed by a
/// ripple that washes down the screen. Completes when the animation ends.
Future<void> playTouchGlow(BuildContext context) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final completer = Completer<void>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => TouchGlow(
      onDone: () {
        entry.remove();
        if (!completer.isCompleted) completer.complete();
      },
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class TouchGlow extends StatefulWidget {
  const TouchGlow({super.key, this.onDone, this.duration = const Duration(milliseconds: 1700)});

  final VoidCallback? onDone;
  final Duration duration;

  @override
  State<TouchGlow> createState() => _TouchGlowState();
}

class _TouchGlowState extends State<TouchGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);
  bool _secondPulse = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _controller
      ..addListener(() {
        if (!_secondPulse && _controller.value > 0.3) {
          _secondPulse = true;
          HapticFeedback.mediumImpact();
        }
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone?.call();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: TouchGlowPainter(_controller.value),
        ),
      ),
    );
  }
}

class TouchGlowPainter extends CustomPainter {
  TouchGlowPainter(this.t);

  /// Animation progress, 0..1.
  final double t;

  static double _interval(double t, double begin, double end, [Curve curve = Curves.linear]) {
    final v = ((t - begin) / (end - begin)).clamp(0.0, 1.0);
    return curve.transform(v);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final origin = Offset(w / 2, -h * 0.02);
    final fadeOut = 1 - _interval(t, 0.6, 1.0, Curves.easeIn);

    // 1. Edge glow: the whole screen border lights up briefly.
    final edge = math.sin(math.pi * _interval(t, 0.0, 0.75)) * fadeOut;
    if (edge > 0) {
      final rect = Offset.zero & size;
      final rrect = RRect.fromRectAndRadius(rect.deflate(2), const Radius.circular(36));
      final edgePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.9 * edge),
            KColors.cyan.withValues(alpha: 0.7 * edge),
            KColors.violet.withValues(alpha: 0.5 * edge),
            KColors.pink.withValues(alpha: 0.2 * edge),
          ],
        ).createShader(rect);
      canvas.drawRRect(rrect, edgePaint);
    }

    // 2. Wave front travelling from the top edge down the screen.
    final wave = _interval(t, 0.1, 0.92, Curves.easeInOutCubic);
    if (wave > 0 && wave < 1) {
      final radius = wave * h * 1.3;
      final strength = math.pow(1 - wave, 0.6).toDouble() * fadeOut;

      // Light wash left behind by the wave.
      final washRect = Rect.fromCircle(center: origin, radius: radius);
      canvas.drawCircle(
        origin,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.10 * strength),
              KColors.cyan.withValues(alpha: 0.06 * strength),
              Colors.transparent,
            ],
            stops: const [0.0, 0.85, 1.0],
          ).createShader(washRect),
      );

      void ring(Color color, double width, double blur, double alpha) {
        canvas.drawCircle(
          origin,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..color = color.withValues(alpha: alpha * strength)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
        );
      }

      ring(KColors.violet, 90 + 60 * wave, 40, 0.55);
      ring(KColors.cyan, 36 + 24 * wave, 18, 0.8);
      ring(Colors.white, 6, 4, 0.95);
    }

    // 3. Bloom where the two phones meet.
    final bloom = _interval(t, 0.0, 0.35, Curves.easeOutCubic) * fadeOut;
    if (bloom > 0) {
      final r = w * (0.18 + 0.45 * bloom);
      final rect = Rect.fromCenter(center: origin, width: r * 2.4, height: r * 1.4);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.95 * bloom),
              KColors.cyan.withValues(alpha: 0.7 * bloom),
              KColors.violet.withValues(alpha: 0.35 * bloom),
              Colors.transparent,
            ],
            stops: const [0.0, 0.3, 0.65, 1.0],
          ).createShader(rect)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
      );
    }
  }

  @override
  bool shouldRepaint(TouchGlowPainter oldDelegate) => oldDelegate.t != t;
}
