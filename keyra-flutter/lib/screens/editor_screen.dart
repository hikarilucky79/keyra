import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/daemon_provider.dart';
import '../providers/ui_provider.dart';
import '../theme/keyra_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/quick_pick.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  String? _selectedKey;
  final Map<String, String> _mappings = {};
  final Map<String, double> _volumes = {};
  bool _isModified = false;

  final List<List<String>> _keyboardRows = [
    ['esc', 'f1', 'f2', 'f3', 'f4', 'f5', 'f6', 'f7', 'f8', 'f9', 'f10', 'f11', 'f12'],
    ['grave', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', 'minus', 'equal', 'backspace'],
    ['tab', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', 'leftbrace', 'rightbrace', 'backslash'],
    ['capslock', 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'semicolon', 'apostrophe', 'enter'],
    ['left_shift', 'z', 'x', 'c', 'v', 'b', 'n', 'm', 'comma', 'dot', 'slash', 'right_shift'],
    ['left_ctrl', 'left_meta', 'left_alt', 'space', 'right_alt', 'right_meta', 'right_ctrl'],
  ];

  @override
  void initState() {
    super.initState();
    // Initialize with current pack state if possible
    // Note: In a real app, we'd fetch the full config from the daemon
  }

  Future<void> _pickFile() async {
    if (_selectedKey == null) return;

    final daemon = Provider.of<DaemonProvider>(context, listen: false);
    
    final home = Platform.environment['HOME'];
    if (home == null) return;

    final packsDir = '$home/.config/keyra/packs';
    final directory = Directory(packsDir);
    List<QuickPickItem> quickItems = [];

    if (directory.existsSync()) {
      // Recursive scan to get files from ALL packs
      final files = directory.listSync(recursive: true).whereType<File>().where((file) {
        final ext = file.path.split('.').last.toLowerCase();
        return ['wav', 'mp3', 'ogg', 'flac'].contains(ext);
      }).toList();

      quickItems = files.map((file) {
        final relativePath = file.path.replaceFirst('$packsDir/', '');
        final parts = relativePath.split('/');
        final packNameOfFile = parts.length > 1 ? parts.first : 'Root';
        final fileName = parts.last;
        
        return QuickPickItem(
          label: fileName,
          subLabel: 'from $packNameOfFile',
          icon: Icons.audiotrack_rounded,
          value: relativePath, // Store relative path for previewing and mapping
        );
      }).toList();
    }

    // Add browse option
    quickItems.add(const QuickPickItem(
      label: 'Browse other files...',
      subLabel: 'Open system file picker',
      icon: Icons.folder_open_rounded,
      value: '__browse__',
    ));

    final selected = await QuickPickOverlay.show(
      context: context,
      title: 'Select audio for ${_getKeyLabel(_selectedKey!)}',
      items: quickItems,
    );

    if (selected == null) return;

    if (selected.value == '__browse__') {
      final dirToOpen = directory.existsSync() ? packsDir : packsDir; // Always packs root for browsing
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3', 'ogg', 'flac'],
        initialDirectory: dirToOpen,
      );

      if (result != null) {
        setState(() {
          _mappings[_selectedKey!] = result.files.single.name;
          _isModified = true;
        });
      }
    } else {
      final relativePath = selected.value as String;
      final fullPath = '$packsDir/$relativePath';
      
      setState(() {
        // We store the relative path from the 'packs' root to keep it portable but specific
        _mappings[_selectedKey!] = relativePath;
        _isModified = true;
      });
      
      // Preview sound with full path
      daemon.triggerPlayDirect(fullPath);
    }
  }

  void _savePack() {
    final daemon = Provider.of<DaemonProvider>(context, listen: false);
    final ui = Provider.of<UiProvider>(context, listen: false);
    final packName = ui.editingPackName ?? daemon.state.pack;

    // Create a Mechvibes-style config
    final config = {
      'name': packName,
      'key_define_type': 'multi',
      'definitions': _mappings,
      'volumes': _volumes, // Extension to support per-key volume
    };
    daemon.savePackConfig(packName, config);
    setState(() => _isModified = false);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sound Pack saved successfully')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.watch<UiProvider>();
    final daemon = context.watch<DaemonProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sound Pack Editor',
                    style: KeyraTheme.h1.copyWith(
                      color: ui.accentColor,
                      fontSize: 32,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: ui.accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: ui.accentColor.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          'Editing',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: ui.accentColor,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        ui.editingPackName ?? daemon.state.pack,
                        style: KeyraTheme.bodyMuted.copyWith(color: KeyraTheme.text),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              if (_isModified)
                ElevatedButton.icon(
                  onPressed: _savePack,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ui.accentColor,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.save_rounded, size: 20),
                  label: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w700)),
                ).animate().fadeIn().scale(curve: Curves.elasticOut, duration: 600.ms),
            ],
          ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1),

          const SizedBox(height: 32),

          // Main Editor Area
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Keyboard Visualization
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: KeyraTheme.mantle.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: _keyboardRows.asMap().entries.map((entry) {
                          final rowIndex = entry.key;
                          final row = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: row.map((key) => _buildKey(key, ui)).toList(),
                            ),
                          ).animate().fadeIn(delay: (100 * rowIndex).ms).slideY(begin: 0.05);
                        }).toList(),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 24),

                // Side Panel: Key details
                Expanded(
                  flex: 1,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildDetailsPanel(ui),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKey(String key, UiProvider ui) {
    final isSelected = _selectedKey == key;
    final hasMapping = _mappings.containsKey(key);

    return GestureDetector(
      onTap: () => setState(() => _selectedKey = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        constraints: BoxConstraints(
          minWidth: _getKeyWidth(key),
        ),
        decoration: BoxDecoration(
          color: isSelected 
              ? ui.accentColor 
              : (hasMapping ? KeyraTheme.surface1.withValues(alpha: 0.8) : KeyraTheme.surface0.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected 
                ? Colors.white.withValues(alpha: 0.5) 
                : Colors.white.withValues(alpha: 0.05),
            width: 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: ui.accentColor.withValues(alpha: 0.4),
              blurRadius: 15,
              spreadRadius: 1,
            )
          ] : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              offset: const Offset(0, 2),
              blurRadius: 4,
            )
          ],
        ),
        child: Center(
          child: Text(
            _getKeyLabel(key),
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? Colors.black : (hasMapping ? Colors.white : KeyraTheme.subtext0.withValues(alpha: 0.6)),
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsPanel(UiProvider ui) {
    if (_selectedKey == null) {
      return GlassCard(
        key: const ValueKey('empty'),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.keyboard_outlined, size: 48, color: ui.accentColor.withValues(alpha: 0.2)),
              const SizedBox(height: 16),
              Text(
                'Select a key to edit',
                style: KeyraTheme.bodyMuted,
              ),
            ],
          ),
        ),
      );
    }

    final mapping = _mappings[_selectedKey];
    final volume = _volumes[_selectedKey] ?? 1.0;

    return GlassCard(
      key: ValueKey(_selectedKey),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ui.accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ui.accentColor.withValues(alpha: 0.2)),
                ),
                child: Icon(Icons.ads_click_rounded, size: 18, color: ui.accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KEY CONFIG',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: ui.accentColor,
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      _getKeyLabel(_selectedKey!),
                      style: KeyraTheme.h3.copyWith(fontSize: 18),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Audio File
          _buildPanelSection(
            label: 'AUDIO SAMPLE',
            child: Column(
              children: [
                InkWell(
                  onTap: _pickFile,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: mapping != null 
                          ? KeyraTheme.green.withValues(alpha: 0.05) 
                          : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: mapping != null 
                            ? KeyraTheme.green.withValues(alpha: 0.2) 
                            : Colors.white.withValues(alpha: 0.05)
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          mapping != null ? Icons.music_note_rounded : Icons.add_rounded,
                          size: 18,
                          color: mapping != null ? KeyraTheme.green : KeyraTheme.subtext0,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            mapping ?? 'Choose sound file...',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: mapping != null ? FontWeight.w600 : FontWeight.w400,
                              color: mapping != null ? Colors.white : KeyraTheme.subtext0,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (mapping != null)
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 14, color: KeyraTheme.red),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => setState(() {
                              _mappings.remove(_selectedKey);
                              _isModified = true;
                            }),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Volume
          _buildPanelSection(
            label: 'GAIN / VELOCITY',
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(volume * 100).toInt()}%', 
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)
                    ),
                    Icon(
                      volume > 0.7 ? Icons.volume_up_rounded : (volume > 0.3 ? Icons.volume_down_rounded : Icons.volume_mute_rounded),
                      size: 14, 
                      color: ui.accentColor.withValues(alpha: 0.6)
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: ui.accentColor,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.05),
                    thumbColor: Colors.white,
                    overlayColor: ui.accentColor.withValues(alpha: 0.2),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: volume,
                    onChanged: (v) => setState(() {
                      _volumes[_selectedKey!] = v;
                      _isModified = true;
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideX(begin: 0.02);
  }

  Widget _buildPanelSection({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: KeyraTheme.subtext0.withValues(alpha: 0.5),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  double _getKeyWidth(String key) {
    switch (key) {
      case 'backspace': return 58;
      case 'tab': return 42;
      case 'enter': return 62;
      case 'capslock': return 52;
      case 'left_shift': return 72;
      case 'right_shift': return 72;
      case 'space': return 180;
      case 'left_ctrl':
      case 'right_ctrl':
      case 'left_alt':
      case 'right_alt':
      case 'left_meta':
      case 'right_meta': return 48;
      default: return 30;
    }
  }

  String _getKeyLabel(String key) {
    switch (key) {
      case 'grave': return '~';
      case 'minus': return '-';
      case 'equal': return '=';
      case 'backspace': return 'DELETE';
      case 'leftbrace': return '[';
      case 'rightbrace': return ']';
      case 'backslash': return '\\';
      case 'semicolon': return ';';
      case 'apostrophe': return '\'';
      case 'left_shift': return 'SHIFT';
      case 'right_shift': return 'SHIFT';
      case 'left_ctrl': return 'CTRL';
      case 'right_ctrl': return 'CTRL';
      case 'left_alt': return 'ALT';
      case 'right_alt': return 'ALT';
      case 'left_meta': return 'SUPER';
      case 'right_meta': return 'SUPER';
      default: return key.toUpperCase();
    }
  }
}
