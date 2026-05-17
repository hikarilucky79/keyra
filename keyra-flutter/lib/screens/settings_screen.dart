/// Settings Screen
///
/// Configuration view with volume control, pack selection,
/// toggle, and daemon info.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/daemon_provider.dart';
import '../services/autostart_service.dart';
import '../theme/keyra_theme.dart';
import '../widgets/glass_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autostartEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadAutostartState();
  }

  Future<void> _loadAutostartState() async {
    final enabled = await AutostartService.isEnabled();
    if (mounted) {
      setState(() {
        _autostartEnabled = enabled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final daemon = context.watch<DaemonProvider>();
    final state = daemon.state;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: KeyraTheme.foreground,
            ),
          ),
          const SizedBox(height: 16),

          // ── General Settings ──────────────────────────────
          _buildSection(
            title: 'General Settings',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Iniciar com o sistema',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Inicializa o Keyra automaticamente ao fazer login.',
                      style: TextStyle(
                        fontSize: 11,
                        color: KeyraTheme.foregroundSubtle,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: _autostartEnabled,
                  activeThumbColor: KeyraTheme.primary,
                  activeTrackColor: KeyraTheme.primary.withValues(alpha: 0.3),
                  inactiveThumbColor: KeyraTheme.foregroundSubtle,
                  inactiveTrackColor: KeyraTheme.surfaceVariant,
                  onChanged: (val) async {
                    await AutostartService.setEnabled(val);
                    setState(() {
                      _autostartEnabled = val;
                    });
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── App Profiles ──────────────────────────────────
          _buildSection(
            title: 'Per-App Profiles',
            child: Column(
              children: [
                if (state.appProfiles.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No custom profiles. Add one to switch packs based on the active window.',
                      style: TextStyle(
                        fontSize: 12,
                        color: KeyraTheme.foregroundSubtle,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ...state.appProfiles.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.key,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: KeyraTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          e.value,
                          style: const TextStyle(
                            color: KeyraTheme.foregroundMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        color: KeyraTheme.error.withValues(alpha: 0.7),
                        onPressed: () => daemon.setAppProfile(e.key, null),
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: 8),
                _buildActionButton(
                  label: 'Add New Profile',
                  icon: Icons.add_rounded,
                  isFullWidth: true,
                  onTap: () => _showAddAppProfileDialog(context, daemon),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Actions ────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _buildActionTile(
                  icon: Icons.refresh_rounded,
                  label: 'Reload Config',
                  onTap: daemon.reloadConfig,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionTile(
                  icon: Icons.download_rounded,
                  label: 'Import Pack',
                  onTap: () => _importPack(daemon),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Updates ────────────────────────────────────────
          _buildSection(
            title: 'Updates',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.availableUpdate != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: KeyraTheme.mauve.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(KeyraTheme.radiusMd),
                      border: Border.all(color: KeyraTheme.mauve.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.update_rounded, color: KeyraTheme.mauve, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Version ${state.availableUpdate!.version} is available!',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          state.availableUpdate!.changelog,
                          style: const TextStyle(
                            fontSize: 11,
                            color: KeyraTheme.foregroundMuted,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: daemon.performUpdate,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: KeyraTheme.mauve,
                                  foregroundColor: Colors.black,
                                  minimumSize: const Size(0, 32),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(KeyraTheme.radiusSm),
                                  ),
                                ),
                                child: const Text('Update Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: daemon.dismissUpdate,
                              child: const Text('Later', style: TextStyle(fontSize: 12, color: KeyraTheme.foregroundSubtle)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Keyra is up to date',
                            style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            'Stable version 0.1.0',
                            style: TextStyle(fontSize: 11, color: KeyraTheme.foregroundSubtle),
                          ),
                        ],
                      ),
                      _buildActionButton(
                        label: 'Check for Updates',
                        onTap: daemon.checkUpdate,
                      ),
                    ],
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Daemon Info ────────────────────────────────────
          if (state.connected) _buildDaemonInfo(state),
        ],
      ),
    );
  }

  void _showAddAppProfileDialog(BuildContext context, DaemonProvider daemon) {
    String appName = '';
    String packName = '';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: KeyraTheme.surface,
          title: const Text('Add App Profile', style: TextStyle(color: Colors.white, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'App Name (e.g. code, discord)',
                  labelStyle: TextStyle(color: KeyraTheme.foregroundMuted, fontSize: 13),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: KeyraTheme.border)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: KeyraTheme.primary)),
                ),
                onChanged: (val) => appName = val,
              ),
              const SizedBox(height: 12),
              TextField(
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Pack Name (e.g. typewriter)',
                  labelStyle: TextStyle(color: KeyraTheme.foregroundMuted, fontSize: 13),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: KeyraTheme.border)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: KeyraTheme.primary)),
                ),
                onChanged: (val) => packName = val,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: KeyraTheme.foregroundMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: KeyraTheme.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (appName.isNotEmpty && packName.isNotEmpty) {
                  daemon.setAppProfile(appName.toLowerCase().trim(), packName.trim());
                }
                Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _importPack(DaemonProvider daemon) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result != null && result.files.single.path != null) {
      daemon.importSoundpack(result.files.single.path!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Importing ${result.files.single.name}...'),
            backgroundColor: KeyraTheme.primary,
          ),
        );
      }
    }
  }

  Widget _buildSection({required String title, required Widget child}) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: KeyraTheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: KeyraTheme.foreground,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KeyraTheme.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: KeyraTheme.primary),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: KeyraTheme.foregroundMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    IconData? icon,
    bool isFullWidth = false,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KeyraTheme.radiusSm),
        child: Container(
          width: isFullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: KeyraTheme.primaryMuted.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(KeyraTheme.radiusSm),
            border: Border.all(color: KeyraTheme.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: KeyraTheme.primary),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: KeyraTheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDaemonInfo(DaemonState state) {
    final uptimeSeconds = state.uptimeMs ~/ 1000;
    final minutes = uptimeSeconds ~/ 60;
    final seconds = uptimeSeconds % 60;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Daemon Info',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KeyraTheme.foreground,
            ),
          ),
          const SizedBox(height: 12),
          _infoRow('Clients connected', '${state.clientsConnected}'),
          const SizedBox(height: 6),
          _infoRow('Uptime', '${minutes}m ${seconds}s'),
          const SizedBox(height: 6),
          _infoRow('Latency', '${state.latency.toStringAsFixed(1)}ms'),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: KeyraTheme.foregroundMuted,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            color: KeyraTheme.foreground,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
