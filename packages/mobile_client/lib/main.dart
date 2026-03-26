import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:common/common.dart';
import 'package:provider/provider.dart';

import 'database/mobile_database.dart';
import 'providers/album_provider.dart';
import 'providers/cleanup_provider.dart';
import 'providers/media_list_provider.dart';
import 'providers/restore_provider.dart';
import 'providers/upload_queue_provider.dart';
import 'screens/browse_screen.dart';
import 'screens/cleanup_screen.dart';
import 'screens/help_screen.dart';
import 'screens/upload_screen.dart';
import 'services/connection_service.dart';
import 'services/discovery_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = MobileDatabase();
  await db.init();
  runApp(MyApp(db: db));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.db});

  final MobileDatabase db;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectionService()),
        ChangeNotifierProvider(create: (_) => DiscoveryService()),
        ChangeNotifierProvider(create: (_) => AlbumProvider()),
        ChangeNotifierProvider(create: (_) => MediaListProvider()),
        ChangeNotifierProvider(create: (_) => CleanupProvider()),
        ChangeNotifierProvider(create: (_) => UploadQueueProvider()),
        ChangeNotifierProvider(create: (_) => RestoreProvider()),
      ],
      child: MaterialApp(
        title: 'PhotoSync 照片搬家',
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
          Locale('zh'),
        ],
        home: MainNavigation(db: db),
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key, required this.db});
  final MobileDatabase db;

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _index = 0;
  // Track which screens have been visited to enable lazy init
  final Set<int> _visited = {0};

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final screens = [
      BrowseScreen(db: widget.db),
      const UploadScreen(),
      const CleanupScreen(),
      const HelpScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: List.generate(screens.length, (i) {
          if (!_visited.contains(i)) {
            return const SizedBox.shrink();
          }
          return screens[i];
        }),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _index = i;
          _visited.add(i);
        }),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.photo_library_outlined),
            selectedIcon: const Icon(Icons.photo_library),
            label: l.navBrowse,
          ),
          NavigationDestination(
            icon: const Icon(Icons.upload_outlined),
            selectedIcon: const Icon(Icons.upload),
            label: l.navUpload,
          ),
          NavigationDestination(
            icon: const Icon(Icons.cleaning_services_outlined),
            selectedIcon: const Icon(Icons.cleaning_services),
            label: l.navCleanUp,
          ),
          NavigationDestination(
            icon: const Icon(Icons.help_outline),
            selectedIcon: const Icon(Icons.help),
            label: l.navHelp,
          ),
        ],
      ),
    );
  }
}
