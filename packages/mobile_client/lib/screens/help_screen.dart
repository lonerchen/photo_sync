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
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(icon: Icons.info_outline, title: l.helpWhatTitle, content: l.helpWhatContent),
          const SizedBox(height: 12),
          _SectionCard(icon: Icons.checklist_outlined, title: l.helpPrereqTitle, steps: [l.helpPrereqStep1, l.helpPrereqStep2, l.helpPrereqStep3]),
          const SizedBox(height: 12),
          _SectionCard(icon: Icons.wifi_outlined, title: l.helpStep1Title, steps: [l.helpStep1_1, l.helpStep1_2, l.helpStep1_3]),
          const SizedBox(height: 12),
          _SectionCard(icon: Icons.upload_outlined, title: l.helpStep2Title, steps: [l.helpStep2_1, l.helpStep2_2, l.helpStep2_3, l.helpStep2_4]),
          const SizedBox(height: 12),
          _SectionCard(icon: Icons.cleaning_services_outlined, title: l.helpStep3Title, steps: [l.helpStep3_1, l.helpStep3_2, l.helpStep3_3, l.helpStep3_4]),
          const SizedBox(height: 12),
          _SectionCard(icon: Icons.cloud_outlined, title: l.helpCloudTitle, content: l.helpCloudContent),
          const SizedBox(height: 12),
          _SectionCard(icon: Icons.restore_outlined, title: l.helpRestoreTitle, content: l.helpRestoreContent),
          const SizedBox(height: 12),
          const _SectionCard(
            icon: Icons.privacy_tip_outlined,
            title: '设备信息说明',
            content:
                '为便于在存储端区分不同手机，本应用会读取设备基础信息（如设备名称、型号）用于局域网连接展示和设备管理，不会采集通讯录、短信、定位等无关信息，也不会上传到第三方云服务。',
          ),
          const SizedBox(height: 12),
          _SectionCard(icon: Icons.warning_amber_outlined, title: l.helpNotesTitle, steps: [l.helpNote1, l.helpNote2, l.helpNote3, l.helpNote4]),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
              ],
            ),
            const SizedBox(height: 10),
            if (content != null)
              Text(content!, style: const TextStyle(fontSize: 14, height: 1.5)),
            if (steps != null)
              ...steps!.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${e.key + 1}. ', style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.primary, fontSize: 14)),
                      Expanded(child: Text(e.value, style: const TextStyle(fontSize: 14, height: 1.4))),
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
