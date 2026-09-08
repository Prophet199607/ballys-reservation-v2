import 'package:flutter/material.dart';

/// The three bouncing dots WhatsApp draws inside a bubble while the other
/// person is writing.
///
/// Each dot runs the same curve a beat behind the one before it, so the row
/// reads as a wave rather than three lights blinking together. The animation
/// is purely decorative — it carries no state of its own and stops with the
/// widget.
class TypingDots extends StatefulWidget {
  const TypingDots({
    super.key,
    this.color = const Color(0xFF8696A0),
    this.dotSize = 7,
    this.spacing = 4,
  });

  final Color color;
  final double dotSize;
  final double spacing;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  /// How far into the cycle each dot starts. The last one still finishes
  /// inside the cycle, so the wave loops without a visible seam.
  static const List<double> _offsets = [0.0, 0.15, 0.30];

  /// The slice of the cycle one dot spends moving; the rest of it rests.
  static const double _span = 0.55;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _offsets.length; i++) ...[
              if (i > 0) SizedBox(width: widget.spacing),
              _dot(_progress(_offsets[i])),
            ],
          ],
        );
      },
    );
  }

  /// This dot's position in its own rise-and-fall, 0 → 1 → 0.
  double _progress(double offset) {
    final t = (_controller.value - offset) % 1.0;
    if (t > _span) return 0;
    return Curves.easeInOut.transform(
      // A half-cycle up then back down, so the dot lands where it started.
      1 - (2 * (t / _span) - 1).abs(),
    );
  }

  Widget _dot(double t) {
    return Transform.translate(
      // Rises by about half its own height at the peak.
      offset: Offset(0, -widget.dotSize * 0.45 * t),
      child: Container(
        width: widget.dotSize,
        height: widget.dotSize,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.45 + 0.55 * t),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
