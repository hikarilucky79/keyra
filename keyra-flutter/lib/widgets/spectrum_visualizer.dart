import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/keyra_theme.dart';

class SpectrumVisualizer extends StatefulWidget {
  final ValueNotifier<double> peakNotifier;
  final int barCount;
  final double width;
  final double height;
  final Color? color;

  const SpectrumVisualizer({
    super.key,
    required this.peakNotifier,
    this.barCount = 12,
    this.width = 60,
    this.height = 20,
    this.color,
  });

  @override
  State<SpectrumVisualizer> createState() => _SpectrumVisualizerState();
}

class _SpectrumVisualizerState extends State<SpectrumVisualizer> with SingleTickerProviderStateMixin {
  late List<double> _barHeights;
  late List<double> _targetHeights;
  late AnimationController _controller;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _barHeights = List.filled(widget.barCount, 0.1);
    _targetHeights = List.filled(widget.barCount, 0.1);
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();

    widget.peakNotifier.addListener(_onPeakChanged);
  }

  void _onPeakChanged() {
    final peak = widget.peakNotifier.value;
    if (peak > 0.01) {
      for (int i = 0; i < widget.barCount; i++) {
        // Higher peak = higher bars, with some randomness for "spectral" look
        _targetHeights[i] = (peak * 0.5 + _random.nextDouble() * peak * 0.5).clamp(0.1, 1.0);
      }
    }
  }

  @override
  void dispose() {
    widget.peakNotifier.removeListener(_onPeakChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Smoothly interpolate towards targets
        for (int i = 0; i < widget.barCount; i++) {
          _barHeights[i] = lerpDouble(_barHeights[i], _targetHeights[i], 0.2)!;
          // Natural decay
          _targetHeights[i] = math.max(0.1, _targetHeights[i] * 0.92);
        }

        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(widget.barCount, (i) {
              return Container(
                width: widget.width / (widget.barCount * 1.5),
                height: widget.height * _barHeights[i],
                decoration: BoxDecoration(
                  color: widget.color ?? KeyraTheme.primary.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(1),
                  boxShadow: [
                    if (_barHeights[i] > 0.5)
                      BoxShadow(
                        color: (widget.color ?? KeyraTheme.primary).withValues(alpha: 0.3),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                  ],
                ),
              );
            }),
          ),
        );
      },
    );
  }

  double? lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }
}
