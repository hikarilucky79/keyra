import 'package:flutter/material.dart';
import '../../../theme/keyra_theme.dart';
import '../../../providers/daemon_provider.dart';
import '../../../widgets/wave_animation.dart';

class StatusFooter extends StatelessWidget {
  final DaemonState state;

  const StatusFooter({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (state.playing) _buildPlayingIndicator(),
        if (state.connected) 
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _buildLatencyIndicator(),
          ),
      ],
    );
  }

  Widget _buildPlayingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: KeyraTheme.mauve.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(100),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WaveAnimation(active: true, height: 12, barCount: 3),
          SizedBox(width: 8),
          Text(
            'SYSTEM AUDIO ACTIVE',
            style: TextStyle(
              fontSize: 9,
              color: KeyraTheme.mauve,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatencyIndicator() {
    final latency = state.latency;
    final color = latency < 15
        ? KeyraTheme.green
        : latency < 30
            ? KeyraTheme.yellow
            : KeyraTheme.red;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'LATENCY:',
          style: TextStyle(
            fontSize: 8,
            color: KeyraTheme.overlay0.withValues(alpha: 0.7),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${latency.toStringAsFixed(1)}ms',
          style: TextStyle(
            fontSize: 9,
            color: color.withValues(alpha: 0.8),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
