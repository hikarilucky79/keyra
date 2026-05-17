/// Status Indicator Widget
///
/// Pulsating dot with glow effect to show connection status.
library;

import 'package:flutter/material.dart';

import '../theme/keyra_theme.dart';

class StatusIndicator extends StatefulWidget {
  final bool connected;
  final double size;
  final String? label;

  const StatusIndicator({
    super.key,
    required this.connected,
    this.size = 8,
    this.label,
  });

  @override
  State<StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends State<StatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.connected) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(StatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.connected && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.connected ? KeyraTheme.success : KeyraTheme.foregroundSubtle;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: widget.connected
                    ? [
                        BoxShadow(
                          color: color.withValues(
                            alpha: 0.5 * _pulseAnimation.value,
                          ),
                          blurRadius: 6 * _pulseAnimation.value,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            );
          },
        ),
        if (widget.label != null) ...[
          const SizedBox(width: 6),
          Text(
            widget.label!,
            style: const TextStyle(
              fontSize: 11,
              color: KeyraTheme.foregroundMuted,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }
}
