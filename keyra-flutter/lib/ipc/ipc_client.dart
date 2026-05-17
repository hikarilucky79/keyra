/// Keyra IPC Client
///
/// Manages direct Unix Domain Socket connection to the Keyra Rust daemon.
/// Uses length-prefixed JSON framing: [4 bytes LE length][JSON payload]
/// Supports auto-reconnect with exponential backoff and heartbeat ping.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const _uuid = Uuid();

/// Maximum allowed frame size (1 MB). Frames exceeding this are rejected
/// to prevent memory exhaustion from corrupt or malicious data.
const _maxFrameSize = 1048576;

/// Length of the frame header in bytes (uint32 LE).
const _headerSize = 4;

/// How often we send a PING to keep the connection alive.
const _heartbeatInterval = Duration(seconds: 2);

/// Ceiling for exponential backoff on reconnect attempts.
const _maxReconnectDelay = Duration(seconds: 30);

class KeyraIpcClient {
  // ── Connection state ─────────────────────────────────────────────
  RawSocket? _socket;
  bool _connected = false;
  bool _disposed = false;

  // ── Streams ──────────────────────────────────────────────────────
  final _eventController = StreamController<DaemonEvent>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  // ── Heartbeat & Reconnect ────────────────────────────────────────
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  double _lastPingMs = 0;
  double _latency = 0;

  // ── Read buffer ──────────────────────────────────────────────────
  final BytesBuilder _readBuffer = BytesBuilder(copy: false);

  // ── Socket path (computed once) ──────────────────────────────────
  late final String _primaryPath = _resolveSocketPath(isPrimary: true);
  late final String _fallbackPath = _resolveSocketPath(isPrimary: false);

  static String _resolveSocketPath({required bool isPrimary}) {
    if (Platform.isWindows) {
      final tempDir = Directory.systemTemp.path;
      final name = isPrimary ? 'keyra.sock' : 'keyra_fallback.sock';
      return '$tempDir${Platform.pathSeparator}$name';
    } else {
      if (isPrimary) {
        final uid = Platform.environment['UID'] ??
            Process.runSync('id', ['-u']).stdout.toString().trim();
        return '/run/user/$uid/keyra.sock';
      } else {
        return '/tmp/keyra.sock';
      }
    }
  }

  // ── Public API ───────────────────────────────────────────────────

  /// Stream of daemon events (STATE_UPDATED, ERROR, PONG, etc.)
  Stream<DaemonEvent> get events => _eventController.stream;

  /// Stream of connection state changes.
  Stream<bool> get connectionState => _connectionController.stream;

  /// Whether the client is currently connected to the daemon.
  bool get isConnected => _connected;

  /// Last measured round-trip latency in milliseconds.
  double get latency => _latency;

  // ═══════════════════════════════════════════════════════════════════
  // Connection lifecycle
  // ═══════════════════════════════════════════════════════════════════

  /// Attempt to connect to the daemon socket.
  /// Tries the XDG runtime path first, then falls back to /tmp.
  Future<void> connect() async {
    if (_disposed || _connected) return;

    for (final path in [_primaryPath, _fallbackPath]) {
      try {
        final addr = InternetAddress(path, type: InternetAddressType.unix);
        _socket = await RawSocket.connect(addr, 0);
        debugPrint('[IPC] Connected to $path');
        _onConnected();
        return;
      } catch (e) {
        debugPrint('[IPC] Failed to connect to $path: $e');
      }
    }

    _scheduleReconnect();
  }

  /// Gracefully close the connection and stop all timers.
  void disconnect() {
    _disposed = true;
    _teardown();
  }

  /// Permanently dispose all resources. No reconnect after this.
  void dispose() {
    disconnect();
    _eventController.close();
    _connectionController.close();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Sending commands
  // ═══════════════════════════════════════════════════════════════════

  /// Send a command to the daemon.
  ///
  /// Silently drops the command if not connected.
  void sendCommand(Command cmd) {
    final socket = _socket;
    if (!_connected || socket == null) return;

    final msg = IpcMessage(
      id: _uuid.v4(),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: cmd.toPayload(),
    );

    final jsonBytes = utf8.encode(msg.encode());
    final frame = Uint8List(_headerSize + jsonBytes.length);

    // Write length header (little-endian uint32)
    final header = ByteData.view(frame.buffer);
    header.setUint32(0, jsonBytes.length, Endian.little);

    // Copy JSON payload after header
    frame.setRange(_headerSize, frame.length, jsonBytes);

    try {
      socket.write(frame);
    } catch (e) {
      debugPrint('[IPC] Send failed: $e');
      _onDisconnected();
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Internal: Connection callbacks
  // ═══════════════════════════════════════════════════════════════════

  void _onConnected() {
    _connected = true;
    _reconnectAttempts = 0;
    _connectionController.add(true);

    _socket!.listen(
      _onSocketEvent,
      onError: (error) {
        debugPrint('[IPC] Socket error: $error');
        _onDisconnected();
      },
      onDone: () {
        debugPrint('[IPC] Socket closed by daemon');
        _onDisconnected();
      },
      cancelOnError: false,
    );

    _startHeartbeat();
  }

  void _onDisconnected() {
    if (!_connected) return; // Already disconnected
    _teardown();

    if (!_disposed) {
      _scheduleReconnect();
    }
  }

  /// Central cleanup: stops heartbeat, closes socket, clears buffer.
  void _teardown() {
    _connected = false;
    _connectionController.add(false);
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _socket?.close();
    _socket = null;
    _readBuffer.clear();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_disposed) return;

    _reconnectAttempts++;

    // Exponential backoff: 1s → 2s → 4s → ... → 30s max
    final delayMs = (1000 * (1 << (_reconnectAttempts - 1).clamp(0, 5)))
        .clamp(1000, _maxReconnectDelay.inMilliseconds);
    final delay = Duration(milliseconds: delayMs);

    debugPrint('[IPC] Reconnecting in ${delay.inMilliseconds}ms '
        '(attempt $_reconnectAttempts)');

    _reconnectTimer = Timer(delay, connect);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Internal: Heartbeat
  // ═══════════════════════════════════════════════════════════════════

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _sendPing());
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _sendPing() {
    _lastPingMs = _nowMs();
    sendCommand(PingCommand(_uuid.v4()));
  }

  // ═══════════════════════════════════════════════════════════════════
  // Internal: Frame reading & parsing
  // ═══════════════════════════════════════════════════════════════════

  void _onSocketEvent(RawSocketEvent event) {
    switch (event) {
      case RawSocketEvent.read:
        final data = _socket?.read();
        if (data != null) {
          _readBuffer.add(data);
          _processBuffer();
        }
      case RawSocketEvent.readClosed:
        _onDisconnected();
      default:
        break;
    }
  }

  /// Drain the read buffer, extracting complete length-prefixed frames.
  void _processBuffer() {
    while (true) {
      final accumulated = _readBuffer.takeBytes();

      // Need at least the 4-byte header
      if (accumulated.length < _headerSize) {
        if (accumulated.isNotEmpty) _readBuffer.add(accumulated);
        return;
      }

      // Read payload length from header
      final header = ByteData.sublistView(
        Uint8List.fromList(accumulated.sublist(0, _headerSize)),
      );
      final payloadLen = header.getUint32(0, Endian.little);

      // Sanity check
      if (payloadLen == 0 || payloadLen > _maxFrameSize) {
        debugPrint('[IPC] Invalid frame length: $payloadLen — resetting');
        _readBuffer.clear();
        return;
      }

      final frameLen = _headerSize + payloadLen;

      // Wait for more data if the frame is incomplete
      if (accumulated.length < frameLen) {
        _readBuffer.add(accumulated);
        return;
      }

      // Extract JSON payload and queue remaining bytes for next iteration
      final jsonBytes = accumulated.sublist(_headerSize, frameLen);
      if (accumulated.length > frameLen) {
        _readBuffer.add(accumulated.sublist(frameLen));
      }

      _decodeAndDispatch(jsonBytes);
    }
  }

  void _decodeAndDispatch(List<int> jsonBytes) {
    try {
      final jsonStr = utf8.decode(jsonBytes);
      final msg = IpcMessage.decode(jsonStr);
      final event = DaemonEvent.fromPayload(msg.payload);

      // Measure latency from PONG responses
      if (event is PongEvent) {
        _latency = _nowMs() - _lastPingMs;
      }

      _eventController.add(event);
    } catch (e) {
      debugPrint('[IPC] Failed to decode message: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Utility
  // ═══════════════════════════════════════════════════════════════════

  /// Current time in milliseconds (high resolution).
  static double _nowMs() =>
      DateTime.now().microsecondsSinceEpoch / 1000.0;
}
