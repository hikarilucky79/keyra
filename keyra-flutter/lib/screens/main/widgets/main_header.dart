import 'package:flutter/material.dart';
import '../../../theme/keyra_theme.dart';
import '../../../providers/daemon_provider.dart';

class MainHeader extends StatelessWidget {
  final DaemonState state;

  const MainHeader({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Premium Brand Logo / Title
        ShaderMask(
          shaderCallback: (bounds) => KeyraTheme.accentGradient.createShader(bounds),
          child: Text(
            'KEYRA',
            style: KeyraTheme.h1.copyWith(
              fontSize: 52,
              fontWeight: FontWeight.w900,
              letterSpacing: -2.0,
              color: Colors.white,
            ),
          ),
        ),
        
        const SizedBox(height: 8),
        
        Text(
          'PREMIUM TYPING ENGINE',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: KeyraTheme.overlay0.withValues(alpha: 0.6),
            letterSpacing: 4.0,
          ),
        ),

        const SizedBox(height: 28),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status badge (pill style) with animation
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: state.enabled
                    ? KeyraTheme.green.withValues(alpha: 0.08)
                    : KeyraTheme.surfaceVariant.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: state.enabled
                      ? KeyraTheme.green.withValues(alpha: 0.2)
                      : KeyraTheme.border.withValues(alpha: 0.1),
                  width: 1,
                ),
                boxShadow: [
                  if (state.enabled)
                    BoxShadow(
                      color: KeyraTheme.green.withValues(alpha: 0.1),
                      blurRadius: 12,
                      spreadRadius: -2,
                    )
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: state.enabled ? KeyraTheme.green : KeyraTheme.overlay0,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    state.enabled ? 'ENGINE ACTIVE' : 'ENGINE PAUSED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: state.enabled ? KeyraTheme.green : KeyraTheme.overlay2,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Version Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'v0.1.0',
                style: TextStyle(
                  fontSize: 10,
                  color: KeyraTheme.overlay0.withValues(alpha: 0.4),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
