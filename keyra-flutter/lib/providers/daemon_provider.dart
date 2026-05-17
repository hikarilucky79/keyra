/// Keyra Daemon State Provider
///
/// Manages the IPC client lifecycle and synchronizes daemon state.
/// Uses ChangeNotifier for reactive UI updates.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ipc/ipc_client.dart';
import '../ipc/models.dart';
import '../services/daemon_launcher.dart';

export '../ipc/models.dart';

class DaemonProvider extends ChangeNotifier {
  final KeyraIpcClient _client = KeyraIpcClient();
  KeyraIpcClient get client => _client;
  final ValueNotifier<double> audioPeakNotifier = ValueNotifier(0.0);

  DaemonState _state = const DaemonState();
  DaemonState get state => _state;

  StreamSubscription<DaemonEvent>? _eventSub;
  StreamSubscription<bool>? _connectionSub;
  Timer? _statusPollTimer;

  DaemonProvider() {
    _connectionSub = _client.connectionState.listen(_onConnectionChanged);
    _eventSub = _client.events.listen(_onEvent);
    
    // Ensure daemon is running before connecting
    DaemonLauncher.ensureRunning().then((success) {
      if (success) {
        _client.connect();
      } else {
        debugPrint('[DaemonProvider] Failed to ensure daemon is running. '
            'Will still attempt to connect in case it was started externally.');
        _client.connect();
      }
    });

    // Poll latency from client periodically
    _statusPollTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateLatency(),
    );
  }

  // ── Connection ────────────────────────────────────────────────────

  void _onConnectionChanged(bool connected) {
    _state = _state.copyWith(connected: connected);
    notifyListeners();
  }

  void _updateLatency() {
    if (_client.isConnected) {
      final lat = _client.latency;
      final history = [..._state.latencyHistory.take(59), lat].toList();
      _state = _state.copyWith(latency: lat, latencyHistory: history);
      notifyListeners();
    }
  }

  // ── Event handling ────────────────────────────────────────────────

  void _onEvent(DaemonEvent event) {
    switch (event) {
      case StateUpdatedEvent e:
        _state = _state.copyWith(
          volume: e.volume,
          pack: e.pack,
          enabled: e.enabled,
          playing: e.playing,
          clientsConnected: e.clientsConnected,
          uptimeMs: e.uptimeMs,
          appProfiles: e.appProfiles,
          availablePacks: e.availablePacks,
          effects: e.effects,
        );
        notifyListeners();
      case PongEvent():
        // Latency is handled by _updateLatency timer
        break;
      case AudioPeakEvent e:
        audioPeakNotifier.value = e.peak;
        break;
      case ErrorEvent e:
        print('[Daemon] Error: ${e.message}');
        break;
      case StatusResponseEvent e:
        _state = _state.copyWith(
          volume: e.volume,
          pack: e.pack,
          enabled: e.enabled,
          playing: e.playing,
          clientsConnected: e.clientsConnected,
          uptimeMs: e.uptimeMs,
          appProfiles: e.appProfiles,
          availablePacks: e.availablePacks,
          effects: e.effects,
        );
        notifyListeners();
      case UpdateAvailableEvent e:
        _state = _state.copyWith(availableUpdate: e);
        notifyListeners();
      case ImportSessionStartedEvent():
      case ImportProgressEvent():
      case ImportFinishedEvent():
        // Handled by ImportService
        break;
    }
  }

  // ── Commands ──────────────────────────────────────────────────────

  void setEnabled(bool enabled) {
    if (enabled) {
      _client.sendCommand(EnableCommand());
    } else {
      _client.sendCommand(DisableCommand());
    }
    _state = _state.copyWith(enabled: enabled);
    notifyListeners();
  }

  void toggleEnabled() {
    setEnabled(!_state.enabled);
  }

  void setVolume(double volume) {
    final v = volume.clamp(0.0, 1.0);
    _client.sendCommand(SetVolumeCommand(v));
    _state = _state.copyWith(volume: v);
    notifyListeners();
  }

  void setPack(String name) {
    _client.sendCommand(SetPackCommand(name));
    _state = _state.copyWith(pack: name);
    notifyListeners();
  }

  void setAppProfile(String appName, String? packName) {
    _client.sendCommand(SetAppProfileCommand(appName: appName, packName: packName));
    
    // Optimistic update
    final newProfiles = Map<String, String>.from(_state.appProfiles);
    if (packName != null) {
      newProfiles[appName] = packName;
    } else {
      newProfiles.remove(appName);
    }
    _state = _state.copyWith(appProfiles: newProfiles);
    notifyListeners();
  }

  void stop() {
    _client.sendCommand(StopCommand());
    _state = _state.copyWith(playing: false);
    notifyListeners();
  }

  void reloadConfig() {
    _client.sendCommand(ReloadConfigCommand());
  }

  void requestStatus() {
    _client.sendCommand(StatusCommand());
  }

  void importSoundpack(String path) {
    _client.sendCommand(ImportRequestCommand(path));
  }

  void savePackConfig(String name, Map<String, dynamic> config) {
    _client.sendCommand(SavePackConfigCommand(name: name, config: config));
  }

  void checkUpdate() {
    _client.sendCommand(CheckUpdateCommand());
  }

  void performUpdate() {
    _client.sendCommand(PerformUpdateCommand());
  }

  void dismissUpdate() {
    _state = _state.copyWith(clearUpdate: true);
    notifyListeners();
  }

  void triggerPlayDirect(String path) {
    _client.sendCommand(PlayDirectCommand(path));
  }

  // ── Lifecycle ─────────────────────────────────────────────────────

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    _eventSub?.cancel();
    _connectionSub?.cancel();
    _client.dispose();
    super.dispose();
  }
}
