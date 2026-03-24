import 'package:common/common.dart';
import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.helpTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _SectionCard(icon: Icons.info_outline, title: l.helpDesktopWhatTitle, content: l.helpDesktopWhatContent),
          const SizedBox(height: 12),
          _SectionCard(icon: Icons.rocket_launch_outlined, title: l.helpDesktopQuickStartTitle, steps: [l.helpDesktopQuickStart1, l.helpDesktopQuickStart2, l.helpDesktopQuickStart3, l.helpDesktopQuickStart4, l.helpDesktopQuickStart5]),
          const SizedBox(height: 12),
          _SectionCard(icon: Icons.photo_library_outlined, title: l.helpDesktopAlbumsTitle, steps: [l.helpDesktopAlbums1, l.helpDesktopAlbums2, l.helpDesktopAlbums3, l.helpDesktopAlbums4]),
          const SizedBox(height: 12),
          _SectionCard(icon: Icons.devices_outlined, title: l.helpDesktopDevicesTitle, content: l.helpDesktopDevicesContent),
          const SizedBox(height: 12),
          _SectionCard(icon: Icons.settings_outlined, title: l.helpDesktopSettingsTitle, content: l.helpDesktopSettingsContent),
          const SizedBox(height: 12),
          _SectionCard(icon: Icons.folder_outlined, title: l.helpDesktopStorageTitle, content: l.helpDesktopStorageContent),
          const SizedBox(height: 12),
          _SectionCard(icon: Icons.warning_amber_outlined, title: l.helpDesktopNotesTitle, steps: [l.helpDesktopNote1, l.helpDesktopNote2, l.helpDesktopNote3, l.helpDesktopNote4]),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.icon, required this.title, this.content, this.steps});

  final IconData icon;
  final String title;
  final String? content;
  final List<String>? steps;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22, color: colorScheme.primary),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            if (content != null)
              Text(content!, style: const TextStyle(fontSize: 14, height: 1.6)),
            if (steps != null)
              ...steps!.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${e.key + 1}. ', style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.primary, fontSize: 14)),
                      Expanded(child: Text(e.value, style: const TextStyle(fontSize: 14, height: 1.5))),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
