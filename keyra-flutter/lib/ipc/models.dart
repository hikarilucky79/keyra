/// Keyra IPC Protocol Models
///
/// Mirrors the Rust daemon's IPC message schema exactly.
/// Protocol: length-prefixed JSON over Unix Domain Socket.
/// Frame: [4 bytes LE length][JSON payload]
library;

import 'dart:convert';

// ---------------------------------------------------------------------------
// Message envelope
// ---------------------------------------------------------------------------

class IpcMessage {
  final String id;
  final int timestampMs;
  final Map<String, dynamic> payload;

  IpcMessage({
    required this.id,
    required this.timestampMs,
    required this.payload,
  });

  factory IpcMessage.fromJson(Map<String, dynamic> json) {
    return IpcMessage(
      id: json['id'] as String,
      timestampMs: json['timestamp_ms'] as int,
      payload: json['payload'] as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp_ms': timestampMs,
        'payload': payload,
      };

  String encode() => jsonEncode(toJson());

  static IpcMessage decode(String raw) {
    return IpcMessage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

// ---------------------------------------------------------------------------
// Commands (UI → Daemon)
// ---------------------------------------------------------------------------

/// Sealed command type matching the Rust enum.
/// Serialized with `"kind": "SCREAMING_SNAKE_CASE"` tag.
sealed class Command {
  Map<String, dynamic> toPayload();
}

class PlayCommand extends Command {
  final String key;
  final double velocity;
  PlayCommand({required this.key, required this.velocity});

  @override
  Map<String, dynamic> toPayload() => {
        'kind': 'PLAY',
        'key': key,
        'velocity': velocity,
      };
}

class StopCommand extends Command {
  @override
  Map<String, dynamic> toPayload() => {'kind': 'STOP'};
}

class EnableCommand extends Command {
  @override
  Map<String, dynamic> toPayload() => {'kind': 'ENABLE'};
}

class DisableCommand extends Command {
  @override
  Map<String, dynamic> toPayload() => {'kind': 'DISABLE'};
}

class SetVolumeCommand extends Command {
  final double volume;
  SetVolumeCommand(this.volume);

  @override
  Map<String, dynamic> toPayload() => {
        'kind': 'SET_VOLUME',
        'volume': volume.clamp(0.0, 1.0),
      };
}

class SetPackCommand extends Command {
  final String name;
  SetPackCommand(this.name);

  @override
  Map<String, dynamic> toPayload() => {
        'kind': 'SET_PACK',
        'name': name,
      };
}

class StatusCommand extends Command {
  @override
  Map<String, dynamic> toPayload() => {'kind': 'STATUS'};
}

class PingCommand extends Command {
  final String nonce;
  PingCommand(this.nonce);

  @override
  Map<String, dynamic> toPayload() => {
        'kind': 'PING',
        'nonce': nonce,
      };
}

class ReloadConfigCommand extends Command {
  @override
  Map<String, dynamic> toPayload() => {'kind': 'RELOAD_CONFIG'};
}


class SetAppProfileCommand extends Command {
  final String appName;
  final String? packName;

  SetAppProfileCommand({required this.appName, this.packName});

  @override
  Map<String, dynamic> toPayload() => {
        'kind': 'SET_APP_PROFILE',
        'app_name': appName,
        'pack_name': packName,
      };
}

class SavePackConfigCommand extends Command {
  final String name;
  final Map<String, dynamic> config;
  SavePackConfigCommand({required this.name, required this.config});

  @override
  Map<String, dynamic> toPayload() => {
        'kind': 'SAVE_PACK_CONFIG',
        'name': name,
        'config': config,
      };
}

class CheckUpdateCommand extends Command {
  @override
  Map<String, dynamic> toPayload() => {'kind': 'CHECK_UPDATE'};
}

class PerformUpdateCommand extends Command {
  @override
  Map<String, dynamic> toPayload() => {'kind': 'PERFORM_UPDATE'};
}

class ImportRequestCommand extends Command {
  final String path;
  ImportRequestCommand(this.path);
  @override
  Map<String, dynamic> toPayload() => {'kind': 'IMPORT_REQUEST', 'path': path};
}

class ImportUpdateMappingCommand extends Command {
  final String fileId;
  final String key;
  ImportUpdateMappingCommand({required this.fileId, required this.key});
  @override
  Map<String, dynamic> toPayload() => {'kind': 'IMPORT_UPDATE_MAPPING', 'file_id': fileId, 'key': key};
}

class ImportProcessCommand extends Command {
  final String name;
  final String author;
  ImportProcessCommand({required this.name, required this.author});
  @override
  Map<String, dynamic> toPayload() => {'kind': 'IMPORT_PROCESS', 'name': name, 'author': author};
}

class ImportPreviewCommand extends Command {
  final String fileId;
  ImportPreviewCommand(this.fileId);
  @override
  Map<String, dynamic> toPayload() => {'kind': 'IMPORT_PREVIEW', 'file_id': fileId};
}

class ImportCancelCommand extends Command {
  @override
  Map<String, dynamic> toPayload() => {'kind': 'IMPORT_CANCEL'};
}

class PlayDirectCommand extends Command {
  final String path;
  PlayDirectCommand(this.path);
  @override
  Map<String, dynamic> toPayload() => {'kind': 'PLAY_DIRECT', 'path': path};
}

// ---------------------------------------------------------------------------
// Shared Models
// ---------------------------------------------------------------------------

class AudioEffects {
  final bool filterEnabled;
  final double filterFrequency;
  final bool reverbEnabled;
  final double reverbWet;

  const AudioEffects({
    this.filterEnabled = false,
    this.filterFrequency = 1000.0,
    this.reverbEnabled = false,
    this.reverbWet = 0.2,
  });

  factory AudioEffects.fromJson(Map<String, dynamic> json) {
    return AudioEffects(
      filterEnabled: json['filter_enabled'] as bool? ?? false,
      filterFrequency: (json['filter_frequency'] as num?)?.toDouble() ?? 1000.0,
      reverbEnabled: json['reverb_enabled'] as bool? ?? false,
      reverbWet: (json['reverb_wet'] as num?)?.toDouble() ?? 0.2,
    );
  }

  Map<String, dynamic> toJson() => {
        'filter_enabled': filterEnabled,
        'filter_frequency': filterFrequency,
        'reverb_enabled': reverbEnabled,
        'reverb_wet': reverbWet,
      };
}

// ---------------------------------------------------------------------------
// Events (Daemon → UI)
// ---------------------------------------------------------------------------

sealed class DaemonEvent {
  factory DaemonEvent.fromPayload(Map<String, dynamic> payload) {
    final kind = payload['kind'] as String;
    return switch (kind) {
      'STATE_UPDATED' => StateUpdatedEvent(
          volume: (payload['volume'] as num).toDouble(),
          pack: payload['pack'] as String,
          enabled: payload['enabled'] as bool,
          playing: payload['playing'] as bool,
          clientsConnected: payload['clients_connected'] as int,
          uptimeMs: payload['uptime_ms'] as int,
          appProfiles: Map<String, String>.from(payload['app_profiles'] ?? {}),
          availablePacks: List<String>.from(payload['available_packs'] ?? []),
          effects: AudioEffects.fromJson(payload['effects'] ?? {}),
        ),
      'UPDATE_AVAILABLE' => UpdateAvailableEvent(
          version: payload['version'] as String,
          changelog: payload['changelog'] as String,
          url: payload['url'] as String,
        ),
      'ERROR' => ErrorEvent(message: payload['message'] as String),
      'PONG' => PongEvent(nonce: payload['nonce'] as String),
      'AUDIO_PEAK' => AudioPeakEvent(peak: (payload['peak'] as num).toDouble()),
      'STATUS_RESPONSE' => StatusResponseEvent(
          volume: (payload['volume'] as num).toDouble(),
          pack: payload['pack'] as String,
          enabled: payload['enabled'] as bool,
          playing: payload['playing'] as bool,
          clientsConnected: payload['clients_connected'] as int,
          latencyMs: (payload['latency_ms'] as num).toDouble(),
          uptimeMs: payload['uptime_ms'] as int,
          appProfiles: Map<String, String>.from(payload['app_profiles'] ?? {}),
          availablePacks: List<String>.from(payload['available_packs'] ?? []),
          effects: AudioEffects.fromJson(payload['effects'] ?? {}),
        ),
      'IMPORT_SESSION_STARTED' => ImportSessionStartedEvent(
          files: payload['files'] as List<dynamic>,
        ),
      'IMPORT_PROGRESS' => ImportProgressEvent(
          progress: (payload['progress'] as num).toDouble(),
          message: payload['message'] as String,
        ),
      'IMPORT_FINISHED' => ImportFinishedEvent(
          packName: payload['pack_name'] as String,
        ),
      _ => ErrorEvent(message: 'Unknown event kind: $kind'),
    };
  }
}

class StateUpdatedEvent implements DaemonEvent {
  final double volume;
  final String pack;
  final bool enabled;
  final bool playing;
  final int clientsConnected;
  final int uptimeMs;
  final Map<String, String> appProfiles;
  final List<String> availablePacks;
  final AudioEffects effects;

  StateUpdatedEvent({
    required this.volume,
    required this.pack,
    required this.enabled,
    required this.playing,
    required this.clientsConnected,
    required this.uptimeMs,
    required this.appProfiles,
    required this.availablePacks,
    required this.effects,
  });
}

class ErrorEvent implements DaemonEvent {
  final String message;
  ErrorEvent({required this.message});
}

class PongEvent implements DaemonEvent {
  final String nonce;
  PongEvent({required this.nonce});
}

class AudioPeakEvent implements DaemonEvent {
  final double peak;
  AudioPeakEvent({required this.peak});
}

class StatusResponseEvent implements DaemonEvent {
  final double volume;
  final String pack;
  final bool enabled;
  final bool playing;
  final int clientsConnected;
  final double latencyMs;
  final int uptimeMs;
  final Map<String, String> appProfiles;
  final List<String> availablePacks;
  final AudioEffects effects;

  StatusResponseEvent({
    required this.volume,
    required this.pack,
    required this.enabled,
    required this.playing,
    required this.clientsConnected,
    required this.latencyMs,
    required this.uptimeMs,
    required this.appProfiles,
    required this.availablePacks,
    required this.effects,
  });
}

class UpdateAvailableEvent implements DaemonEvent {
  final String version;
  final String changelog;
  final String url;
  UpdateAvailableEvent({
    required this.version,
    required this.changelog,
    required this.url,
  });
}

class ImportSessionStartedEvent implements DaemonEvent {
  final List<dynamic> files;
  ImportSessionStartedEvent({required this.files});
}

class ImportProgressEvent implements DaemonEvent {
  final double progress;
  final String message;
  ImportProgressEvent({required this.progress, required this.message});
}

class ImportFinishedEvent implements DaemonEvent {
  final String packName;
  ImportFinishedEvent({required this.packName});
}

// ---------------------------------------------------------------------------
// App State (synchronized from daemon)
// ---------------------------------------------------------------------------

class DaemonState {
  final double volume;
  final String pack;
  final bool enabled;
  final bool playing;
  final int clientsConnected;
  final int uptimeMs;
  final bool connected;
  final double latency;
  final double audioPeak;
  final List<double> latencyHistory;
  final Map<String, String> appProfiles;
  final List<String> availablePacks;
  final AudioEffects effects;
  
  final UpdateAvailableEvent? availableUpdate;

  const DaemonState({
    this.volume = 0.7,
    this.pack = 'default',
    this.enabled = true,
    this.playing = false,
    this.clientsConnected = 0,
    this.uptimeMs = 0,
    this.connected = false,
    this.latency = 0,
    this.audioPeak = 0,
    this.latencyHistory = const [],
    this.appProfiles = const {},
    this.availablePacks = const [],
    this.effects = const AudioEffects(),
    this.availableUpdate,
  });

  DaemonState copyWith({
    double? volume,
    String? pack,
    bool? enabled,
    bool? playing,
    int? clientsConnected,
    int? uptimeMs,
    bool? connected,
    double? latency,
    double? audioPeak,
    List<double>? latencyHistory,
    Map<String, String>? appProfiles,
    List<String>? availablePacks,
    AudioEffects? effects,
    UpdateAvailableEvent? availableUpdate,
    bool clearUpdate = false,
  }) {
    return DaemonState(
      volume: volume ?? this.volume,
      pack: pack ?? this.pack,
      enabled: enabled ?? this.enabled,
      playing: playing ?? this.playing,
      clientsConnected: clientsConnected ?? this.clientsConnected,
      uptimeMs: uptimeMs ?? this.uptimeMs,
      connected: connected ?? this.connected,
      latency: latency ?? this.latency,
      audioPeak: audioPeak ?? this.audioPeak,
      latencyHistory: latencyHistory ?? this.latencyHistory,
      appProfiles: appProfiles ?? this.appProfiles,
      availablePacks: availablePacks ?? this.availablePacks,
      effects: effects ?? this.effects,
      availableUpdate: clearUpdate ? null : (availableUpdate ?? this.availableUpdate),
    );
  }
}
