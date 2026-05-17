import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/daemon_provider.dart';
import '../providers/ui_provider.dart';
import '../theme/keyra_theme.dart';
import '../widgets/glass_card.dart';

class PacksScreen extends StatelessWidget {
  const PacksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final daemon = context.watch<DaemonProvider>();
    final state = daemon.state;
    final packs = state.availablePacks;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sound Library',
                    style: KeyraTheme.h1.copyWith(fontSize: 32),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Browse and manage your ${packs.length} sound packs',
                    style: KeyraTheme.bodyMuted,
                  ),
                ],
              ),
              const Spacer(),
              _buildImportButton(context),
            ],
          ),
          const SizedBox(height: 48),
          
          if (packs.isEmpty)
            _buildEmptyState()
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 24,
                mainAxisSpacing: 24,
                childAspectRatio: 1.6,
              ),
              itemCount: packs.length,
              itemBuilder: (context, index) {
                final packName = packs[index];
                final isSelected = state.pack == packName;
                return _buildPackCard(context, daemon, packName, isSelected);
              },
            ),
          const SizedBox(height: 100), // Space for bottom nav
        ],
      ),
    );
  }

  Widget _buildImportButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: KeyraTheme.mauve.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: () => context.read<UiProvider>().setCurrentView(AppView.import),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Add Pack', style: TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: KeyraTheme.mauve,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const GlassCard(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(48.0),
          child: Column(
            children: [
              Icon(Icons.library_music_rounded, size: 48, color: KeyraTheme.overlay0),
              SizedBox(height: 16),
              Text(
                'No sound packs found',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'Import a .zip or add folders to ~/.config/keyra/packs',
                textAlign: TextAlign.center,
                style: TextStyle(color: KeyraTheme.foregroundMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPackCard(BuildContext context, DaemonProvider daemon, String name, bool isSelected) {
    return GlassCard(
      padding: EdgeInsets.zero,
      showGlow: isSelected,
      onTap: () => daemon.setPack(name),
      border: Border.all(
        color: isSelected ? KeyraTheme.mauve.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.05),
        width: isSelected ? 2 : 1,
      ),
      child: Stack(
        children: [
          // Background Gradient for selection
          if (isSelected)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      KeyraTheme.mauve.withValues(alpha: 0.1),
                      KeyraTheme.pink.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Premium App-Style Icon
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isSelected 
                            ? [KeyraTheme.mauve, KeyraTheme.pink]
                            : [KeyraTheme.surfaceVariant, KeyraTheme.surface1],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: isSelected ? [
                          BoxShadow(
                            color: KeyraTheme.mauve.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ] : null,
                      ),
                      child: Icon(
                        Icons.audiotrack_rounded,
                        size: 22,
                        color: isSelected ? Colors.black : KeyraTheme.mauve,
                      ),
                    ),
                    const Spacer(),
                    // Contextual Action
                    Material(
                      color: Colors.transparent,
                      child: IconButton(
                        onPressed: () {
                          final ui = context.read<UiProvider>();
                          ui.setEditingPackName(name);
                          ui.setCurrentView(AppView.editor);
                        },
                        icon: Icon(
                          Icons.settings_rounded,
                          size: 20,
                          color: isSelected ? Colors.white : KeyraTheme.overlay1,
                        ),
                        hoverColor: Colors.white.withValues(alpha: 0.1),
                        splashRadius: 20,
                        tooltip: 'Configure Pack',
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'MECHANICAL KEYBOARD',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? KeyraTheme.mauve : KeyraTheme.overlay0,
                        letterSpacing: 0.8,
                      ),
                    ),
                    if (isSelected) ...[
                      const Spacer(),
                      const Icon(Icons.check_circle_rounded, size: 14, color: KeyraTheme.mauve),
                      const SizedBox(width: 4),
                      const Text(
                        'ACTIVE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: KeyraTheme.mauve,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
