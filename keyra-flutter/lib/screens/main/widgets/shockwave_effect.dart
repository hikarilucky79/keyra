import 'package:flutter/material.dart';

class ShockwavePainter extends CustomPainter {
  final List<Shockwave> shockwaves;

  ShockwavePainter({required this.shockwaves});

  @override
  void paint(Canvas canvas, Size size) {
    for (var wave in shockwaves) {
      final paint = Paint()
        ..color = wave.color.withValues(alpha: 1.0 - wave.progress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * (1.0 - wave.progress);

      canvas.drawCircle(
        wave.position,
        wave.radius * wave.progress,
        paint,
      );

      // Add a subtle fill
      final fillPaint = Paint()
        ..color = wave.color.withValues(alpha: 0.1 * (1.0 - wave.progress))
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        wave.position,
        wave.radius * wave.progress,
        fillPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ShockwavePainter oldDelegate) => true;
}

class Shockwave {
  final Offset position;
  final double radius;
  final Color color;
  double progress; // 0.0 to 1.0

  Shockwave({
    required this.position,
    this.radius = 80.0,
    required this.color,
    this.progress = 0.0,
  });
}

class ShockwaveEffect extends StatefulWidget {
  final Widget child;
  const ShockwaveEffect({super.key, required this.child});

  static ShockwaveEffectState? of(BuildContext context) {
    return context.findAncestorStateOfType<ShockwaveEffectState>();
  }

  @override
  State<ShockwaveEffect> createState() => ShockwaveEffectState();
}

class ShockwaveEffectState extends State<ShockwaveEffect> with SingleTickerProviderStateMixin {
  final List<Shockwave> _shockwaves = [];
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(() {
        setState(() {
          _shockwaves.removeWhere((w) => w.progress >= 1.0);
          for (var w in _shockwaves) {
            w.progress += 0.05; // Speed of expansion
          }
        });
      });
  }

  void addShockwave(Offset position, Color color) {
    setState(() {
      _shockwaves.add(Shockwave(position: position, color: color));
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ShockwavePainter(shockwaves: _shockwaves),
      child: widget.child,
    );
  }
}
