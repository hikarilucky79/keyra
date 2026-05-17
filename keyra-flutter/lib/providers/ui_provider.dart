/// Keyra UI State Provider
///
/// Manages UI-only state that doesn't need to sync with the daemon.
library;

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

enum AppView { main, packs, editor, settings, import }

class UiProvider extends ChangeNotifier {
  AppView _currentView = AppView.main;
  AppView get currentView => _currentView;

  bool _isSettingsOpen = false;
  bool get isSettingsOpen => _isSettingsOpen;

  bool _isMiniMode = false;
  bool get isMiniMode => _isMiniMode;

  Color _accentColor = const Color(0xffcba6f7); // Default mauve
  Color get accentColor => _accentColor;

  String? _editingPackName;
  String? get editingPackName => _editingPackName;

  void setEditingPackName(String? name) {
    if (_editingPackName != name) {
      _editingPackName = name;
      notifyListeners();
    }
  }

  void toggleMiniMode() {
    _isMiniMode = !_isMiniMode;
    notifyListeners();
  }

  void setCurrentView(AppView view) {
    if (_currentView != view) {
      _currentView = view;
      notifyListeners();
    }
  }

  void setSettingsOpen(bool open) {
    if (_isSettingsOpen != open) {
      _isSettingsOpen = open;
      notifyListeners();
    }
  }

  Future<void> updateThemeFromImage(ImageProvider image) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        image,
        maximumColorCount: 10,
      );
      if (palette.dominantColor != null) {
        _accentColor = palette.dominantColor!.color;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to extract color: $e');
    }
  }
}
