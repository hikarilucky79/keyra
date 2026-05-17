import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Service responsible for locating and launching the Keyra Rust daemon.
class DaemonLauncher {
  static Process? _process;
  static final _stderrController = StreamController<String>.broadcast();
  
  /// Stream of the daemon's stderr output.
  static Stream<String> get stderrStream => _stderrController.stream;

  /// Attempts to launch the Keyra daemon if it's not already running.
  static Future<bool> ensureRunning() async {
    if (_process != null) return true;

    // 1. Check if already running via pgrep (optional, but safer)
    try {
      final result = await Process.run('pgrep', ['-x', 'keyra-daemon']);
      if (result.exitCode == 0) {
        debugPrint('[Launcher] Daemon is already running (pid: ${result.stdout.trim()})');
        return true;
      }
    } catch (_) {
      // pgrep might not be available or other error, proceed to try launch
    }

    // 2. Find the binary
    final binaryPath = await _findBinary();
    if (binaryPath == null) {
      debugPrint('[Launcher] Could not find keyra-daemon binary');
      return false;
    }

    debugPrint('[Launcher] Starting daemon: $binaryPath');
    
    try {
      _process = await Process.start(binaryPath, []);
      
      // Redirect stdout to debugPrint
      _process!.stdout.transform(utf8.decoder).listen((data) {
        for (final line in data.split('\n')) {
          if (line.trim().isNotEmpty) {
            debugPrint('[Daemon] $line');
          }
        }
      });

      // Redirect stderr to debugPrint and broadcast it
      _process!.stderr.transform(utf8.decoder).listen((data) {
        for (final line in data.split('\n')) {
          if (line.trim().isNotEmpty) {
            debugPrint('[Daemon ERROR] $line');
            _stderrController.add(line);
          }
        }
      });

      // Handle process exit
      _process!.exitCode.then((code) {
        debugPrint('[Launcher] Daemon exited with code $code');
        _process = null;
      });

      return true;
    } catch (e) {
      debugPrint('[Launcher] Failed to start daemon: $e');
      return false;
    }
  }

  /// Locate the daemon binary in common development and production paths.
  static Future<String?> _findBinary() async {
    // 1. Check environment variable (useful for custom setups)
    final envPath = Platform.environment['KEYRA_DAEMON_PATH'];
    if (envPath != null && await File(envPath).exists()) return envPath;

    // 2. Check standard system path
    const systemPath = '/usr/bin/keyra-daemon';
    if (await File(systemPath).exists()) return systemPath;

    // 3. Check development paths relative to the executable or CWD
    final List<String> devPaths = [
      // If running from keyra-flutter directory
      '../keyra-daemon/target/release/keyra-daemon',
      '../keyra-daemon/target/debug/keyra-daemon',
      // If running from root directory
      'keyra-daemon/target/release/keyra-daemon',
      'keyra-daemon/target/debug/keyra-daemon',
      // Relative to executable (for bundled apps)
      '${File(Platform.resolvedExecutable).parent.path}/keyra-daemon',
    ];

    for (final path in devPaths) {
      if (await File(path).exists()) {
        return path;
      }
    }

    return null;
  }

  /// Stops the daemon if it was started by this launcher.
  static void stop() {
    _process?.kill();
    _process = null;
  }
}
