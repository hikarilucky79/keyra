import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../../../providers/daemon_provider.dart';
import '../../../providers/ui_provider.dart';
import '../../../theme/keyra_theme.dart';
import '../../../widgets/glass_card.dart';
import '../../../widgets/spectrum_visualizer.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final daemon = context.watch<DaemonProvider>();
    final ui = context.watch<UiProvider>();
    final state = daemon.state;

    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        borderRadius: KeyraTheme.radiusLg,
        child: Row(
          children: [
            // On/Off Toggle
            IconButton(
              onPressed: daemon.toggleEnabled,
              icon: Icon(
                state.enabled ? Icons.power_settings_new_rounded : Icons.power_off_rounded,
                color: state.enabled ? KeyraTheme.mauve : KeyraTheme.overlay0,
              ),
            ),
            
            const SizedBox(width: 8),
            
            // Info
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.pack.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    state.enabled ? 'ACTIVE' : 'DISABLED',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: state.enabled ? KeyraTheme.mauve.withValues(alpha: 0.7) : KeyraTheme.overlay0,
                    ),
                  ),
                ],
              ),
            ),
  
            // Spectrum Visualizer
            if (state.enabled)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SpectrumVisualizer(
                  peakNotifier: daemon.audioPeakNotifier,
                  barCount: 15,
                  width: 50,
                  height: 15,
                  color: KeyraTheme.mauve,
                ),
              ),

            // Exit Mini Mode
            IconButton(
              onPressed: () async {
                ui.toggleMiniMode();
                await windowManager.setHasShadow(true);
                await windowManager.setResizable(true);
                await windowManager.setSize(const Size(850, 600));
                await windowManager.center();
                await windowManager.setAlwaysOnTop(false);
              },
              icon: const Icon(Icons.open_in_full_rounded, size: 18, color: KeyraTheme.overlay0),
            ),
          ],
        ),
      ),
    );
  }
}
