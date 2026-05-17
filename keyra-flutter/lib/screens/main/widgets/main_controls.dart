import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../theme/keyra_theme.dart';
import '../../../providers/daemon_provider.dart';
import '../../../widgets/glass_card.dart';
import 'app_profiles_dialog.dart';

class MainControls extends StatelessWidget {
  final DaemonProvider daemon;
  final DaemonState state;

  const MainControls({
    super.key,
    required this.daemon,
    required this.state,
  });

  Future<void> _importPack(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result != null && result.files.single.path != null) {
        daemon.importSoundpack(result.files.single.path!);
      }
    } catch (e) {
      debugPrint('Failed to pick file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Unified Control Center Panel
        GlassCard(
          padding: const EdgeInsets.all(24),
          borderRadius: 24,
          child: Column(
            children: [
              // ── Master Control Row ──────────────────────────
              Row(
                children: [
                  _buildToggleWithLabel(context),
                  const Spacer(),
                  // Volume Controls
                  _buildVolumeControl(context),
                ],
              ),
              
              const SizedBox(height: 32),
              
              // ── Sound Pack Selection Row ─────────────────────
              Row(
                children: [
                  Expanded(child: _buildPackInfoCard(context)),
                  const SizedBox(width: 16),
                  _buildActionButton(
                    icon: Icons.auto_awesome_mosaic_rounded,
                    onPressed: () => showAppProfilesDialog(context, daemon, state),
                    tooltip: 'App Profiles',
                  ),
                  const SizedBox(width: 12),
                  _buildActionButton(
                    icon: Icons.cloud_download_rounded,
                    onPressed: () => _importPack(context),
                    tooltip: 'Import Pack',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggleWithLabel(BuildContext context) {
    return Row(
      children: [
        _buildPremiumToggle(),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ENGINE STATUS',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: KeyraTheme.overlay0, letterSpacing: 1.0),
            ),
            Text(
              state.enabled ? 'Enabled' : 'Paused',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: state.enabled ? Colors.white : KeyraTheme.overlay2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVolumeControl(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Icon(
            state.volume == 0 ? Icons.volume_off_rounded : 
            state.volume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded,
            size: 18,
            color: KeyraTheme.mauve,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7, elevation: 4),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                value: state.volume,
                onChanged: daemon.setVolume,
                activeColor: KeyraTheme.mauve,
                inactiveColor: KeyraTheme.surface1,
              ),
            ),
          ),
          Text(
            '${(state.volume * 100).toInt()}%',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: KeyraTheme.overlay2,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackInfoCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: KeyraTheme.mauve.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KeyraTheme.mauve.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: KeyraTheme.mauve.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.music_note_rounded, size: 16, color: KeyraTheme.mauve),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ACTIVE SOUND PACK',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: KeyraTheme.overlay0, letterSpacing: 1.2),
                ),
                Text(
                  state.pack,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumToggle() {
    return GestureDetector(
      onTap: daemon.toggleEnabled,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        width: 48,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          gradient: state.enabled 
            ? KeyraTheme.accentGradient
            : const LinearGradient(colors: [KeyraTheme.surface2, KeyraTheme.surface1]),
          boxShadow: state.enabled
              ? [BoxShadow(color: KeyraTheme.mauve.withValues(alpha: 0.4), blurRadius: 12, spreadRadius: -2)]
              : null,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          alignment: state.enabled ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 2))
              ],
            ),
          ),
        ),
      ),
    );
  }
}
