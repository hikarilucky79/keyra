/// Keyra — Premium Typing Sound Engine for Linux
///
/// Flutter Linux Desktop application that communicates directly
/// with the Keyra Rust daemon via Unix Domain Sockets.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import 'package:window_manager/window_manager.dart';

import 'providers/daemon_provider.dart';
import 'providers/ui_provider.dart';
import 'screens/main_screen.dart';
import 'screens/main/widgets/mini_player.dart';
import 'screens/packs_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/editor_screen.dart';
import 'screens/import_wizard.dart';
import 'services/import_service.dart';
import 'services/tray_service.dart';
import 'theme/keyra_theme.dart';
import 'widgets/navigation_bar.dart';
import 'widgets/status_indicator.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final isBackground = args.contains('--background') || args.contains('--minimized');
  
  // Initialize window manager
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(850, 600),
    minimumSize: Size(850, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden, // Hide system bar to avoid double bars
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (!isBackground) {
      await windowManager.show();
      await windowManager.focus();
    }
  });

  runApp(const KeyraApp());
}

class KeyraApp extends StatelessWidget {
  const KeyraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DaemonProvider()),
        ChangeNotifierProvider(create: (_) => UiProvider()),
        ChangeNotifierProvider(
          create: (context) => ImportService(
            Provider.of<DaemonProvider>(context, listen: false).client,
          ),
        ),
      ],
      child: Consumer<UiProvider>(
        builder: (context, ui, _) => MaterialApp(
          title: 'KEYRA',
          debugShowCheckedModeBanner: false,
          theme: KeyraTheme.dark.copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: ui.accentColor,
              brightness: Brightness.dark,
            ),
          ),
          home: const KeyraShell(),
        ),
      ),
    );
  }
}

/// App shell with title bar, content area, and bottom navigation.
class KeyraShell extends StatefulWidget {
  const KeyraShell({super.key});

  @override
  State<KeyraShell> createState() => _KeyraShellState();
}

class _KeyraShellState extends State<KeyraShell> {
  @override
  void initState() {
    super.initState();
    // Initialize TrayService after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final daemon = Provider.of<DaemonProvider>(context, listen: false);
      final ui = Provider.of<UiProvider>(context, listen: false);
      TrayService().init(daemon, ui);
    });
  }

  String? _lastPack;
  void _updateThemeIfNeeded(BuildContext context, String pack, UiProvider ui) {
    if (_lastPack != pack) {
      _lastPack = pack;
      // In a real app, we would load the image from the pack's directory.
      // Since we don't have direct access to the pack's files here (it's in ~/.config/keyra/packs),
      // we'll assume there's an image we can load. 
      // For now, we'll just simulate it or use a default if not found.
      // Ideally, the daemon would provide a URL or path to the cover.
    }
  }

  @override
  Widget build(BuildContext context) {
    final daemon = context.watch<DaemonProvider>();
    final ui = context.watch<UiProvider>();
    final state = daemon.state;

    // Trigger dynamic theme update when pack changes
    _updateThemeIfNeeded(context, state.pack, ui);

    return Scaffold(
      backgroundColor: ui.isMiniMode ? Colors.transparent : KeyraTheme.background,
      body: ui.isMiniMode 
        ? const Center(child: MiniPlayer())
        : Column(
            children: [
              // ── Title Bar ──────────────────────────────────────
              _buildTitleBar(state, ui),

              // ── Main Content ───────────────────────────────────
              Expanded(
                child: Stack(
                  children: [
                    // Page content with animated switcher
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: _buildCurrentView(ui.currentView),
                    ),

                    // Disconnected overlay
                    if (!state.connected) _buildDisconnectedOverlay(),
                  ],
                ),
              ),

              // ── Bottom Navigation ──────────────────────────────
              KeyraNavigationBar(
                currentView: ui.currentView,
                onViewChanged: ui.setCurrentView,
              ),
            ],
          ),
    );
  }

  Widget _buildTitleBar(DaemonState state, UiProvider ui) {
    return GestureDetector(
      onPanStart: (details) => windowManager.startDragging(),
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: KeyraTheme.background,
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.03),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // Current View Indicator
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ui.currentView.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: ui.accentColor,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 20,
                  height: 2,
                  decoration: BoxDecoration(
                    color: ui.accentColor,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
            
            const Spacer(),
            
            // Connection status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (state.connected ? KeyraTheme.green : KeyraTheme.red).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (state.connected ? KeyraTheme.green : KeyraTheme.red).withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                children: [
                  StatusIndicator(
                    connected: state.connected,
                    size: 6,
                    label: '',
                  ),
                  const SizedBox(width: 8),
                  Text(
                    state.connected ? 'STABLE' : 'OFFLINE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: state.connected ? KeyraTheme.green : KeyraTheme.red,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Mini-Mode Button
            _TitleBarButton(
              onPressed: () async {
                ui.toggleMiniMode();
                await windowManager.setAsFrameless();
                await windowManager.setSize(const Size(320, 100));
                await windowManager.setAlwaysOnTop(true);
              },
              icon: Icons.compress_rounded,
              label: 'MINI PLAYER',
            ),

            const SizedBox(width: 16),
            
            // Window Controls (Right side like the user's screenshot)
            Row(
              children: [
                _WindowControlButton(
                  icon: Icons.remove_rounded,
                  onPressed: () => windowManager.minimize(),
                ),
                _WindowControlButton(
                  icon: Icons.close_rounded,
                  onPressed: () => windowManager.close(),
                  isClose: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentView(AppView view) {
    return switch (view) {
      AppView.main => const MainScreen(key: ValueKey('main')),
      AppView.settings => const SettingsScreen(key: ValueKey('settings')),
      AppView.packs => const PacksScreen(key: ValueKey('packs')),
      AppView.editor => const EditorScreen(key: ValueKey('editor')),
      AppView.import => const ImportWizardScreen(key: ValueKey('import')),
    };
  }

  Widget _buildDisconnectedOverlay() {
    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: KeyraTheme.background.withValues(alpha: 0.7),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: KeyraTheme.mantle.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 30,
                      spreadRadius: -5,
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: KeyraTheme.red.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.link_off_rounded, color: KeyraTheme.red, size: 24),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Daemon Unavailable',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Trying to re-establish connection...',
                      style: TextStyle(
                        fontSize: 13,
                        color: KeyraTheme.subtext0,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SizedBox(
                      width: 100,
                      child: LinearProgressIndicator(
                        backgroundColor: KeyraTheme.surface0,
                        color: KeyraTheme.red,
                        minHeight: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ).animate().fadeIn(duration: 300.ms),
    );
  }
}

class _TitleBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _TitleBarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: KeyraTheme.overlay0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _WindowControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;

  const _WindowControlButton({
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      hoverColor: isClose ? Colors.red.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.05),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: 16,
          color: Colors.white.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

