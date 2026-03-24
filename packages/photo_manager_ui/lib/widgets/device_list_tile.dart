import 'package:common/common.dart';
import 'package:flutter/material.dart';

import 'connection_status_badge.dart';

/// A list tile that displays device info with connection status.
class DeviceListTile extends StatelessWidget {
  const DeviceListTile({
    super.key,
    required this.device,
    this.onTap,
    this.selected = false,
  });

  final DeviceInfo device;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      leading: _platformIcon(device.platform),
      title: Text(device.deviceName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConnectionStatusBadge(
            isConnected: device.isConnected,
            isConnecting: false,
          ),
          if (device.storagePath.isNotEmpty)
            Text(
              device.storagePath,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      isThreeLine: device.storagePath.isNotEmpty,
      onTap: onTap,
    );
  }

  Widget _platformIcon(String platform) {
    final icon = switch (platform.toLowerCase()) {
      'ios' => Icons.phone_iphone,
      'android' => Icons.phone_android,
      _ => Icons.devices,
    };
    return Icon(icon, size: 32);
  }
}
