import 'dart:io';

import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/providers.dart';

/// Storage path configuration screen.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<StorageSettingsProvider>();
      await provider.load();
      _pathController.text = provider.storagePath ?? '';
    });
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder(StorageSettingsProvider provider) async {
    // On desktop we use a simple text input since file_picker is not in pubspec.
    // Show a dialog to enter the path manually.
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _PathInputDialog(initial: _pathController.text),
    );
    if (result != null && result.isNotEmpty) {
      _pathController.text = result;
      await _applyPath(provider, result);
    }
  }

  Future<void> _applyPath(StorageSettingsProvider provider, String path) async {
    final ok = await provider.changePath(path);
    if (mounted) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? l.storagePathSaved : provider.validationError ?? l.invalidPath),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: Consumer<StorageSettingsProvider>(
        builder: (context, provider, _) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.storagePath, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(l.storagePathDesc, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pathController,
                        enabled: !provider.isBusy,
                        decoration: InputDecoration(
                          hintText: '/path/to/storage',
                          border: const OutlineInputBorder(),
                          errorText: provider.validationError,
                          suffixIcon: provider.isBusy
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : null,
                        ),
                        onSubmitted: (value) => _applyPath(provider, value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.folder_open),
                      label: Text(l.browse),
                      onPressed: provider.isBusy ? null : () => _pickFolder(provider),
                    ),
                  ],
                ),
                if (provider.isMigrating) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: provider.migrationProgress),
                  const SizedBox(height: 6),
                  Text(
                    provider.migrationMessage,
                    style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                ],
                const SizedBox(height: 8),
                if (provider.isConfigured)
                  _PathStatusRow(path: provider.storagePath!),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PathStatusRow extends StatelessWidget {
  const _PathStatusRow({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final exists = Directory(path).existsSync();
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Icon(
          exists ? Icons.check_circle : Icons.error,
          color: exists ? Colors.green : Colors.red,
          size: 16,
        ),
        const SizedBox(width: 6),
        Text(
          exists ? l.pathExists : l.pathNotExist,
          style: TextStyle(
            color: exists ? Colors.green : Colors.red,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _PathInputDialog extends StatefulWidget {
  const _PathInputDialog({required this.initial});
  final String initial;

  @override
  State<_PathInputDialog> createState() => _PathInputDialogState();
}

class _PathInputDialogState extends State<_PathInputDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.enterStoragePath),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '/Users/me/Photos',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: Text(l.ok),
        ),
      ],
    );
  }
}
