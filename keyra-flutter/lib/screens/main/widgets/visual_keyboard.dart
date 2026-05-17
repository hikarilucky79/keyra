import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../widgets/glass_card.dart';
import '../../../widgets/key_visual.dart';
import '../../../theme/keyra_theme.dart';
import 'shockwave_effect.dart';

class KeyInfo {
  final String label;
  final String key; // Logic key identifier (e.g. 'shift')
  final String id;  // Unique physical ID (e.g. 'shift_l')
  final double widthFactor;

  const KeyInfo(this.label, this.key, this.id, {this.widthFactor = 1.0});
}

class VisualKeyboard extends StatefulWidget {
  final bool enabled;

  const VisualKeyboard({super.key, required this.enabled});

  @override
  State<VisualKeyboard> createState() => _VisualKeyboardState();
}

class _VisualKeyboardState extends State<VisualKeyboard> {
  final Set<String> _activeKeys = {};
  final Map<String, GlobalKey> _keyPositions = {};
  final FocusNode _focusNode = FocusNode();

  static const double _baseUnit = 44;
  static const double _gap = 4;

  // 60% Keyboard Layout with Unique IDs (non-const to avoid hot reload caching issues)
  static final List<List<KeyInfo>> _keyboardLayout = [
    [
      const KeyInfo('', 'escape', 'esc'),
      const KeyInfo('1', '1', '1'),
      const KeyInfo('2', '2', '2'),
      const KeyInfo('3', '3', '3'),
      const KeyInfo('4', '4', '4'),
      const KeyInfo('5', '5', '5'),
      const KeyInfo('6', '6', '6'),
      const KeyInfo('7', '7', '7'),
      const KeyInfo('8', '8', '8'),
      const KeyInfo('9', '9', '9'),
      const KeyInfo('0', '0', '0'),
      const KeyInfo('', '-', 'minus'),
      const KeyInfo('', '+', 'plus'),
      const KeyInfo('', 'backspace', 'backspace', widthFactor: 2.0),
    ],
    [
      const KeyInfo('', 'tab', 'tab', widthFactor: 1.5),
      const KeyInfo('q', 'q', 'q'),
      const KeyInfo('w', 'w', 'w'),
      const KeyInfo('e', 'e', 'e'),
      const KeyInfo('r', 'r', 'r'),
      const KeyInfo('t', 't', 't'),
      const KeyInfo('y', 'y', 'y'),
      const KeyInfo('u', 'u', 'u'),
      const KeyInfo('i', 'i', 'i'),
      const KeyInfo('o', 'o', 'o'),
      const KeyInfo('p', 'p', 'p'),
      const KeyInfo('', '[', 'bracket_l'),
      const KeyInfo('', ']', 'bracket_r'),
      const KeyInfo('', '\\', 'backslash', widthFactor: 1.5),
    ],
    [
      const KeyInfo('', 'caps lock', 'caps', widthFactor: 1.75),
      const KeyInfo('a', 'a', 'a'),
      const KeyInfo('s', 's', 's'),
      const KeyInfo('d', 'd', 'd'),
      const KeyInfo('f', 'f', 'f'),
      const KeyInfo('g', 'g', 'g'),
      const KeyInfo('h', 'h', 'h'),
      const KeyInfo('j', 'j', 'j'),
      const KeyInfo('k', 'k', 'k'),
      const KeyInfo('l', 'l', 'l'),
      const KeyInfo('', ';', 'semicolon'),
      const KeyInfo('', '\'', 'quote'),
      const KeyInfo('', 'enter', 'enter', widthFactor: 2.25),
    ],
    [
      const KeyInfo('', 'shift', 'shift_l', widthFactor: 2.25),
      const KeyInfo('z', 'z', 'z'),
      const KeyInfo('x', 'x', 'x'),
      const KeyInfo('c', 'c', 'c'),
      const KeyInfo('v', 'v', 'v'),
      const KeyInfo('b', 'b', 'b'),
      const KeyInfo('n', 'n', 'n'),
      const KeyInfo('m', 'm', 'm'),
      const KeyInfo('', ',', 'comma'),
      const KeyInfo('', '.', 'period'),
      const KeyInfo('', '/', 'slash'),
      const KeyInfo('', 'shift', 'shift_r', widthFactor: 2.75),
    ],
    [
      const KeyInfo('', 'control', 'ctrl_l', widthFactor: 1.25),
      const KeyInfo('', 'meta', 'win_l', widthFactor: 1.25),
      const KeyInfo('', 'alt', 'alt_l', widthFactor: 1.25),
      const KeyInfo('SPACE', ' ', 'space', widthFactor: 6.25),
      const KeyInfo('', 'meta', 'win_r', widthFactor: 1.25),
      const KeyInfo('', 'alt', 'alt_r', widthFactor: 1.25),
      const KeyInfo('', 'fn', 'fn', widthFactor: 1.25),
      const KeyInfo('', 'control', 'ctrl_r', widthFactor: 1.25),
    ],
  ];

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    final keyLabel = event.logicalKey.keyLabel.toLowerCase();
    String mappingKey = _getMappingKey(event);

    setState(() {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        _activeKeys.add(mappingKey);
        _activeKeys.add(keyLabel);

        // Shockwave trigger
        final keyKey = _keyPositions[mappingKey] ?? _keyPositions[keyLabel];
        if (event is KeyDownEvent && keyKey != null) {
          _triggerShockwave(keyKey);
        }
      } else if (event is KeyUpEvent) {
        _activeKeys.remove(mappingKey);
        _activeKeys.remove(keyLabel);
      }
    });
  }

  String _getMappingKey(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.shiftLeft) return 'shift_l';
    if (key == LogicalKeyboardKey.shiftRight) return 'shift_r';
    if (key == LogicalKeyboardKey.controlLeft) return 'ctrl_l';
    if (key == LogicalKeyboardKey.controlRight) return 'ctrl_r';
    if (key == LogicalKeyboardKey.altLeft) return 'alt_l';
    if (key == LogicalKeyboardKey.altRight) return 'alt_r';
    if (key == LogicalKeyboardKey.metaLeft) return 'win_l';
    if (key == LogicalKeyboardKey.metaRight) return 'win_r';
    final label = key.keyLabel.toLowerCase();
    return label == ' ' ? 'space' : label;
  }

  void _triggerShockwave(GlobalKey keyKey) {
    final renderBox = keyKey.currentContext?.findRenderObject() as RenderBox?;
    final parentBox = _shockwaveKey.currentContext?.findRenderObject() as RenderBox?;
    
    if (renderBox != null && parentBox != null) {
      final offset = renderBox.localToGlobal(
        Offset(renderBox.size.width / 2, renderBox.size.height / 2),
        ancestor: parentBox,
      );
      _shockwaveKey.currentState?.addShockwave(offset, KeyraTheme.mauve);
    }
  }

  // Clear keys when focus is lost to prevent "stuck" keys
  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      setState(() {
        _activeKeys.clear();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  final GlobalKey<ShockwaveEffectState> _shockwaveKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: widget.enabled ? _handleKeyEvent : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KeyraTheme.mantle.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.02),
              offset: const Offset(0, -2),
              blurRadius: 0,
            ),
          ],
        ),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          borderRadius: 20,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.03),
            width: 0.5,
          ),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            opacity: widget.enabled ? 1.0 : 0.3,
            child: ShockwaveEffect(
              key: _shockwaveKey,
              child: FittedBox(
                fit: BoxFit.contain,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _keyboardLayout.map((row) {
                    final visibleKeys = row.where((info) => info.label.isNotEmpty || info.id == 'space').toList();
                    if (visibleKeys.isEmpty) return const SizedBox.shrink();
                    
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: _gap / 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: visibleKeys.map((info) {
                          final keyKey = _keyPositions.putIfAbsent(info.id, () => GlobalKey());
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: _gap / 2),
                            child: KeyVisual(
                              key: keyKey,
                              keyName: info.label,
                              isActive: _activeKeys.contains(info.id) || _activeKeys.contains(info.key),
                              width: info.widthFactor * _baseUnit,
                              height: _baseUnit,
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
