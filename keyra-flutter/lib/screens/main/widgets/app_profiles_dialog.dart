import 'package:flutter/material.dart';
import '../../../theme/keyra_theme.dart';
import '../../../providers/daemon_provider.dart';

void showAppProfilesDialog(BuildContext context, DaemonProvider daemon, DaemonState state) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: KeyraTheme.mantle,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KeyraTheme.radiusLg)),
        title: const Text('Per-App Profiles',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.appProfiles.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text('No per-app profiles configured.',
                      style: TextStyle(color: KeyraTheme.overlay0, fontSize: 13)),
                ),
              ...state.appProfiles.entries.map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: KeyraTheme.surface0.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(KeyraTheme.radiusMd),
                    ),
                    child: ListTile(
                      title: Text(e.key,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text('Pack: ${e.value}',
                          style: const TextStyle(
                              color: KeyraTheme.mauve, fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: KeyraTheme.red, size: 20),
                        onPressed: () {
                          daemon.setAppProfile(e.key, null);
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showAddAppProfileDialog(context, daemon);
            },
            child: const Text('Add Profile',
                style: TextStyle(color: KeyraTheme.mauve, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close',
                style: TextStyle(color: KeyraTheme.overlay0)),
          ),
        ],
      );
    },
  );
}

void _showAddAppProfileDialog(BuildContext context, DaemonProvider daemon) {
  String appName = '';
  String packName = '';

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: KeyraTheme.mantle,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KeyraTheme.radiusLg)),
        title: const Text('Add App Profile',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'App Name (e.g. code, discord)',
                labelStyle: TextStyle(color: KeyraTheme.overlay0, fontSize: 12),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: KeyraTheme.surface1)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: KeyraTheme.mauve)),
              ),
              onChanged: (val) => appName = val,
            ),
            const SizedBox(height: 12),
            TextField(
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Pack Name (e.g. typewriter)',
                labelStyle: TextStyle(color: KeyraTheme.overlay0, fontSize: 12),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: KeyraTheme.surface1)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: KeyraTheme.mauve)),
              ),
              onChanged: (val) => packName = val,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: KeyraTheme.overlay0)),
          ),
          TextButton(
            onPressed: () {
              if (appName.isNotEmpty && packName.isNotEmpty) {
                daemon.setAppProfile(appName.toLowerCase().trim(), packName.trim());
              }
              Navigator.pop(context);
            },
            child: const Text('Add',
                style: TextStyle(color: KeyraTheme.mauve, fontWeight: FontWeight.w700)),
          ),
        ],
      );
    },
  );
}
