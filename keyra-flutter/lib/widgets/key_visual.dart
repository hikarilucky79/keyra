/// Key Visual Widget
///
/// Animated keyboard key that reacts to press/release events
/// with scale, color, and glow animations.

library;

import 'package:flutter/material.dart';

import '../theme/keyra_theme.dart';

class KeyVisual extends StatelessWidget {
  final String keyName;
  final bool isActive;
  final double width;
  final double height;

  const KeyVisual({
    super.key,
    required this.keyName,
    required this.isActive,
    this.width = 44,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      width: width,
      height: height,
      transform: Matrix4.diagonal3Values(isActive ? 0.96 : 1.0, isActive ? 0.96 : 1.0, 1.0),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isActive
              ? [KeyraTheme.mauve, KeyraTheme.mauve.withValues(alpha: 0.8)]
              : [
                  KeyraTheme.surface1.withValues(alpha: 0.9),
                  KeyraTheme.surface0,
                ],
        ),
        border: Border.all(
          color: isActive
              ? Colors.white.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.1),
          width: 0.5,
        ),
        boxShadow: [
          // Outer shadow for depth
          BoxShadow(
            color: Colors.black.withValues(alpha: isActive ? 0.2 : 0.4),
            blurRadius: isActive ? 4 : 8,
            offset: Offset(0, isActive ? 1 : 4),
            spreadRadius: isActive ? 0 : -1,
          ),
          // Top highlight (bezel effect)
          if (!isActive)
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.05),
              offset: const Offset(0, -1),
              blurRadius: 0,
            ),
          // Glow for active state
          if (isActive)
            BoxShadow(
              color: KeyraTheme.mauve.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: isActive
              ? null
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.1, 1.0],
                  colors: [
                    Colors.white.withValues(alpha: 0.05),
                    Colors.transparent,
                    Colors.transparent,
                  ],
                ),
        ),
        child: Center(
          child: Text(
            keyName.toUpperCase(),
            style: TextStyle(
              fontSize: keyName.length > 2 ? 8 : 11,
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.black.withValues(alpha: 0.9) : KeyraTheme.text.withValues(alpha: 0.9),
              letterSpacing: 0.5,
              fontFamily: 'Inter',
            ),
          ),
        ),
      ),
    );
  }
}
