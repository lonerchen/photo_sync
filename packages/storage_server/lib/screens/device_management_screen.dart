import 'package:flutter/material.dart';
import 'package:photo_manager_ui/photo_manager_ui.dart';
import 'package:provider/provider.dart';

import '../providers/providers.dart';

/// Shows the list of known devices with their connection status.
class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({super.key});

  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeviceListProvider>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<DeviceListProvider>().refresh(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Consumer<DeviceListProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.devices.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.devices, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No devices connected yet'),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: provider.devices.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final device = provider.devices[index];
              return DeviceListTile(device: device);
            },
          );
        },
      ),
    );
  }
}
