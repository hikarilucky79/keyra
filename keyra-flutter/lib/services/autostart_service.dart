import 'dart:io';

/// Service to manage system autostart integration for Keyra.
/// Supports Linux (via ~/.config/autostart/ desktop files)
/// and Windows (via Registry HKCU\Software\Microsoft\Windows\CurrentVersion\Run entries).
class AutostartService {
  static const String _desktopFileName = 'keyra.desktop';
  static const String _windowsRegistryKey = 'Keyra';

  /// Get the standard autostart file path on Linux
  static Future<File?> get _desktopFile async {
    if (!Platform.isLinux) return null;
    
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      return null;
    }
    
    return File('$home/.config/autostart/$_desktopFileName');
  }

  /// Check if autostart is currently enabled
  static Future<bool> isEnabled() async {
    try {
      if (Platform.isLinux) {
        final file = await _desktopFile;
        if (file == null) return false;
        return await file.exists();
      } else if (Platform.isWindows) {
        // Query the Windows Registry
        final result = await Process.run('reg', [
          'query',
          'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run',
          '/v',
          _windowsRegistryKey,
        ]);
        return result.exitCode == 0;
      }
      return false;
    } catch (e) {
      stderr.writeln('[Autostart] Error checking enabled status: $e');
      return false;
    }
  }

  /// Enable or disable autostart
  static Future<void> setEnabled(bool enabled) async {
    try {
      if (Platform.isLinux) {
        final file = await _desktopFile;
        if (file == null) return;

        if (enabled) {
          // Ensure parent autostart directory exists
          await file.parent.create(recursive: true);

          // Determine executable path
          final appImage = Platform.environment['APPIMAGE'];
          final execPath = appImage ?? Platform.resolvedExecutable;

          final desktopContent = '''[Desktop Entry]
Type=Application
Name=Keyra
Comment=Premium typing sound engine for Linux
Exec=$execPath --background
Icon=keyra
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
''';
          await file.writeAsString(desktopContent);
          stdout.writeln('[Autostart] Successfully enabled Linux autostart pointing to: $execPath');
        } else {
          if (await file.exists()) {
            await file.delete();
            stdout.writeln('[Autostart] Successfully disabled Linux autostart');
          }
        }
      } else if (Platform.isWindows) {
        if (enabled) {
          final execPath = Platform.resolvedExecutable;
          // Add registry entry using standard reg.exe tool present on all Windows versions
          final result = await Process.run('reg', [
            'add',
            'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run',
            '/v',
            _windowsRegistryKey,
            '/t',
            'REG_SZ',
            '/d',
            '"$execPath" --background',
            '/f', // Overwrite if already exists
          ]);
          if (result.exitCode == 0) {
            stdout.writeln('[Autostart] Successfully enabled Windows Registry autostart pointing to: $execPath');
          } else {
            stderr.writeln('[Autostart] Failed to add Windows Registry entry: ${result.stderr}');
          }
        } else {
          // Remove registry entry
          final result = await Process.run('reg', [
            'delete',
            'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run',
            '/v',
            _windowsRegistryKey,
            '/f', // Force delete without prompt
          ]);
          if (result.exitCode == 0) {
            stdout.writeln('[Autostart] Successfully disabled Windows Registry autostart');
          } else {
            // Reg delete returns exit code 1 if the key doesn't exist, which is fine
            stderr.writeln('[Autostart] Windows Registry entry deletion resolved with exit code: ${result.exitCode}');
          }
        }
      }
    } catch (e) {
      stderr.writeln('[Autostart] Error setting autostart: $e');
    }
  }
}
