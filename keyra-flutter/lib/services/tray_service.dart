import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/daemon_provider.dart';
import '../providers/ui_provider.dart';

/// Service managing the system tray integration for Keyra.
/// Handles left-click toggles, right-click quick controls,
/// and reactive status synchronization.
class TrayService with TrayListener {
  static final TrayService _instance = TrayService._internal();
  factory TrayService() => _instance;
  TrayService._internal();

  DaemonProvider? _daemon;
  bool _initialized = false;

  Future<void> init(DaemonProvider daemon, UiProvider ui) async {
    if (_initialized) {
      // Prevent duplicate listeners
      _daemon?.removeListener(_onDaemonStateChanged);
    }
    
    _daemon = daemon;
    trayManager.addListener(this);
    
    // Register listener so the tray menu dynamically updates on daemon state changes
    _daemon!.addListener(_onDaemonStateChanged);
    
    _initialized = true;
    await _updateTray();
  }

  void _onDaemonStateChanged() {
    _updateTray();
  }

  Future<void> _updateTray() async {
    if (_daemon == null) return;

    final state = _daemon!.state;
    final volumePercent = (state.volume * 100).round();
    
    // Set tray icon
    // Using a fallback path, will bundle this icon inside assets
    await trayManager.setIcon(
      'assets/icons/tray_icon.png',
    );

    final isVisible = await windowManager.isVisible();

    List<MenuItem> items = [
      MenuItem(
        key: 'show_hide',
        label: isVisible ? 'Esconder Janela' : 'Mostrar Janela',
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'mute_toggle',
        label: state.enabled ? 'Silenciar (Mute)' : 'Ativar som (Unmute)',
      ),
      MenuItem(
        key: 'vol_up',
        label: 'Aumentar Volume (+10%) [Atual: $volumePercent%]',
      ),
      MenuItem(
        key: 'vol_down',
        label: 'Diminuir Volume (-10%)',
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'exit',
        label: 'Sair',
      ),
    ];

    await trayManager.setContextMenu(Menu(items: items));
  }

  /// Left-click toggles window visibility (Show & Focus / Hide)
  @override
  void onTrayIconMouseDown() {
    windowManager.isVisible().then((isVisible) {
      if (isVisible) {
        windowManager.hide();
      } else {
        windowManager.show();
        windowManager.focus();
      }
    });
  }

  /// Right-click pops up the context menu containing quick controls
  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  /// Handles quick control interactions clicked from the tray menu
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (_daemon == null) return;

    switch (menuItem.key) {
      case 'show_hide':
        windowManager.isVisible().then((isVisible) {
          if (isVisible) {
            windowManager.hide();
          } else {
            windowManager.show();
            windowManager.focus();
          }
        });
        break;
      case 'mute_toggle':
        _daemon!.setEnabled(!_daemon!.state.enabled);
        break;
      case 'vol_up':
        final newVol = (_daemon!.state.volume + 0.1).clamp(0.0, 1.0);
        _daemon!.setVolume(newVol);
        break;
      case 'vol_down':
        final newVol = (_daemon!.state.volume - 0.1).clamp(0.0, 1.0);
        _daemon!.setVolume(newVol);
        break;
      case 'exit':
        _daemon!.dispose();
        windowManager.close();
        break;
    }
  }
}
