/// Glass Card Widget
///
/// A frosted-glass card with backdrop blur, subtle border,
/// and optional gradient glow effect.
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/keyra_theme.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;
  final bool showGlow;
  final VoidCallback? onTap;
  final BoxBorder? border;
  final Color? color;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = KeyraTheme.radiusLg,
    this.showGlow = false,
    this.onTap,
    this.border,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: showGlow ? KeyraTheme.glowShadow : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: (color ?? KeyraTheme.card).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(borderRadius),
                border: border ??
                    Border.all(
                      color: KeyraTheme.border.withValues(alpha: 0.15),
                      width: 0.5,
                    ),
                boxShadow: KeyraTheme.macShadow,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
