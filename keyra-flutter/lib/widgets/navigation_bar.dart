/// Keyra Navigation Bar
///
/// Bottom navigation bar with animated indicator and glassmorphism.
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../providers/ui_provider.dart';
import '../theme/keyra_theme.dart';

class KeyraNavigationBar extends StatelessWidget {
  final AppView currentView;
  final ValueChanged<AppView> onViewChanged;

  const KeyraNavigationBar({
    super.key,
    required this.currentView,
    required this.onViewChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: KeyraTheme.mantle.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.05),
                width: 0.5,
              ),
              boxShadow: KeyraTheme.macShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: AppView.values.where((v) => v != AppView.import).map((view) {
                final isActive = view == currentView;
                return _NavItem(
                  label: view == AppView.main ? 'Main' : view.name[0].toUpperCase() + view.name.substring(1),
                  icon: _iconForView(view),
                  isActive: isActive,
                  onTap: () => onViewChanged(view),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForView(AppView view) {
    return switch (view) {
      AppView.main => Icons.keyboard_rounded,
      AppView.settings => Icons.tune_rounded,
      AppView.packs => Icons.library_music_rounded,
      AppView.editor => Icons.edit_note_rounded,
      AppView.import => Icons.download_rounded,
    };
  }
}


class _NavItem extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isActive
                  ? KeyraTheme.mauve.withValues(alpha: 0.15)
                  : _hovering
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 18,
                  color: widget.isActive
                      ? KeyraTheme.mauve
                      : KeyraTheme.subtext0,
                ),
                const SizedBox(width: 8),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        widget.isActive ? FontWeight.w700 : FontWeight.w500,
                    color: widget.isActive
                        ? KeyraTheme.mauve
                        : KeyraTheme.subtext0,
                    letterSpacing: 0.5,
                  ),
                  child: Text(widget.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
