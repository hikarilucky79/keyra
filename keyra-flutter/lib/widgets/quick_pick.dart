import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/keyra_theme.dart';

class QuickPickItem {
  final String label;
  final String? subLabel;
  final IconData? icon;
  final dynamic value;

  const QuickPickItem({
    required this.label,
    this.subLabel,
    this.icon,
    this.value,
  });
}

class QuickPickOverlay extends StatefulWidget {
  final String title;
  final List<QuickPickItem> items;
  final ValueChanged<QuickPickItem> onSelected;

  const QuickPickOverlay({
    super.key,
    required this.title,
    required this.items,
    required this.onSelected,
  });

  static Future<QuickPickItem?> show({
    required BuildContext context,
    required String title,
    required List<QuickPickItem> items,
  }) {
    return showGeneralDialog<QuickPickItem>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'QuickPick',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return QuickPickOverlay(
          title: title,
          items: items,
          onSelected: (item) => Navigator.of(context).pop(item),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<QuickPickOverlay> createState() => _QuickPickOverlayState();
}

class _QuickPickOverlayState extends State<QuickPickOverlay> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  int _selectedIndex = 0;
  List<QuickPickItem> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    _focusNode.requestFocus();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    setState(() {
      _filteredItems = widget.items
          .where((item) =>
              item.label.toLowerCase().contains(_searchController.text.toLowerCase()))
          .toList();
      _selectedIndex = 0;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _selectedIndex = (_selectedIndex + 1) % _filteredItems.length;
        });
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _selectedIndex = (_selectedIndex - 1 + _filteredItems.length) % _filteredItems.length;
        });
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_filteredItems.isNotEmpty) {
          widget.onSelected(_filteredItems[_selectedIndex]);
        }
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: KeyboardListener(
          focusNode: FocusNode(),
          onKeyEvent: _handleKeyEvent,
          child: Container(
            width: 500,
            constraints: const BoxConstraints(maxHeight: 400),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: KeyraTheme.mantle.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black,
                  blurRadius: 40,
                  spreadRadius: -5,
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Search Bar
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, size: 18, color: KeyraTheme.overlay0),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _focusNode,
                              decoration: InputDecoration(
                                hintText: widget.title,
                                hintStyle: const TextStyle(color: KeyraTheme.overlay0, fontSize: 14),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              onSubmitted: (_) {
                                if (_filteredItems.isNotEmpty) {
                                  widget.onSelected(_filteredItems[_selectedIndex]);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    // List
                    Flexible(
                      child: _filteredItems.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(32.0),
                              child: Text(
                                'No matches found',
                                style: TextStyle(color: KeyraTheme.overlay0, fontSize: 13),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _filteredItems.length,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemBuilder: (context, index) {
                                final item = _filteredItems[index];
                                final isSelected = index == _selectedIndex;

                                return GestureDetector(
                                  onTap: () => widget.onSelected(item),
                                  child: MouseRegion(
                                    onEnter: (_) => setState(() => _selectedIndex = index),
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isSelected ? KeyraTheme.mauve.withValues(alpha: 0.1) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isSelected ? KeyraTheme.mauve.withValues(alpha: 0.2) : Colors.transparent,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            item.icon ?? Icons.chevron_right_rounded,
                                            size: 16,
                                            color: isSelected ? KeyraTheme.mauve : KeyraTheme.overlay2,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.label,
                                                  style: TextStyle(
                                                    color: isSelected ? Colors.white : KeyraTheme.text,
                                                    fontSize: 13,
                                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                                  ),
                                                ),
                                                if (item.subLabel != null)
                                                  Text(
                                                    item.subLabel!,
                                                    style: const TextStyle(
                                                      color: KeyraTheme.overlay0,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          if (isSelected)
                                            const Icon(Icons.keyboard_return_rounded, size: 14, color: KeyraTheme.overlay0),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
