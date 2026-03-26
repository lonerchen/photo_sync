import 'dart:async';
import 'dart:io';

import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'album_browser_screen.dart';
import 'device_management_screen.dart';
import 'help_screen.dart';
import 'settings_screen.dart';

/// Root shell with a NavigationRail on the left and content on the right.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  String _localIp = '...';
  Timer? _ipTimer;

  @override
  void initState() {
    super.initState();
    _loadIp();
    // 每 5 秒检测一次 IP 变化，桌面端没有网络变化回调，轮询是最可靠的方式
    _ipTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadIp());
  }

  @override
  void dispose() {
    _ipTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            setState(() => _localIp = addr.address);
            return;
          }
        }
      }
    } catch (_) {}
    setState(() => _localIp = 'N/A');
  }

  static const _screens = [
    AlbumBrowserScreen(),
    DeviceManagementScreen(),
    SettingsScreen(),
    HelpScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final destinations = [
      NavigationRailDestination(
        icon: const Icon(Icons.photo_library_outlined),
        selectedIcon: const Icon(Icons.photo_library),
        label: Text(l.navAlbums),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.devices_outlined),
        selectedIcon: const Icon(Icons.devices),
        label: Text(l.navDevices),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: Text(l.navSettings),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.help_outline),
        selectedIcon: const Icon(Icons.help),
        label: Text(l.navHelp),
      ),
    ];

    return Scaffold(
      body: Column(
        children: [
          Container(
            // Use `surface` for broad Flutter SDK compatibility.
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.wifi, size: 14, color: Colors.green),
                const SizedBox(width: 6),
                Text(l.serverAddress, style: const TextStyle(fontSize: 12)),
                SelectableText(
                  '$_localIp:8765',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy, size: 14),
                  tooltip: l.copy,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '$_localIp:8765'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l.copied),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) =>
                      setState(() => _selectedIndex = index),
                  labelType: NavigationRailLabelType.all,
                  destinations: destinations,
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: _screens[_selectedIndex]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
