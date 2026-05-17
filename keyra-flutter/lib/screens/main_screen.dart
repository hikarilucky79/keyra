/// Main Screen (Refactored)
///
/// Primary view showing the visual keyboard, audio controls,
/// and daemon connection status with premium animations.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/daemon_provider.dart';
import '../theme/keyra_theme.dart';
import 'main/widgets/main_header.dart';
import 'main/widgets/visual_keyboard.dart';
import 'main/widgets/main_controls.dart';
import 'main/widgets/status_footer.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final daemon = context.watch<DaemonProvider>();
    final state = daemon.state;

    return Container(
      color: KeyraTheme.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          children: [
            const SizedBox(height: 20),

            // ── Header (Logo, Version, Status) ──────────────
            MainHeader(state: state),

            const SizedBox(height: 48),

            // ── Keyboard Visualizer ──────────────────────────
            VisualKeyboard(enabled: state.enabled),

            const SizedBox(height: 48),

            // ── Main Controls (Toggle, Volume, Packs) ────────
            MainControls(daemon: daemon, state: state),

            const SizedBox(height: 40),

            // ── Status Footer (Latency, Playing) ───────────
            StatusFooter(state: state),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
