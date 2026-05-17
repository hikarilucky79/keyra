/// Volume Slider Widget
///
/// Premium custom slider with gradient track, glow thumb,
/// and real-time percentage label.
library;

import 'package:flutter/material.dart';

import '../theme/keyra_theme.dart';

class VolumeSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final double width;

  const VolumeSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 140,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          value == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          size: 18,
          color: KeyraTheme.foregroundMuted,
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: width,
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: KeyraTheme.primary,
              inactiveTrackColor: KeyraTheme.border,
              thumbColor: KeyraTheme.primary,
              overlayColor: KeyraTheme.primary.withValues(alpha: 0.12),
              trackHeight: 4,
              thumbShape: const _GlowThumbShape(),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: 1,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            '${(value * 100).round()}%',
            style: const TextStyle(
              fontSize: 11,
              color: KeyraTheme.foregroundMuted,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _GlowThumbShape extends SliderComponentShape {
  const _GlowThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(8);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;

    // Glow
    final glowPaint = Paint()
      ..color = KeyraTheme.primary.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, 10, glowPaint);

    // Thumb
    final thumbPaint = Paint()..color = KeyraTheme.primary;
    canvas.drawCircle(center, 7, thumbPaint);

    // Inner dot
    final innerPaint = Paint()..color = const Color(0xFF0A0A0F);
    canvas.drawCircle(center, 3, innerPaint);
  }
}
