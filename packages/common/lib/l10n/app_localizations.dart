import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

/// Minimal hand-written localizations for zh and en.
/// Usage: AppLocalizations.of(context).someKey
abstract class AppLocalizations {
  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  // ---------------------------------------------------------------------------
  // Common / Navigation
  // ---------------------------------------------------------------------------
  String get appTitle;
  String get navBrowse;
  String get navUpload;
  String get navCleanUp;
  String get navHelp;
  String get navAlbums;
  String get navDevices;
  String get navSettings;

  // ---------------------------------------------------------------------------
  // Server address bar (desktop)
  // ---------------------------------------------------------------------------
  String get serverAddress;
  String get copied;
  String get copy;

  // ---------------------------------------------------------------------------
  // Browse screen
  // ---------------------------------------------------------------------------
  String get browseTitle;
  String get selectToRestore;
  String get restorePhotos;
  String get exitRestoreMode;
  String get notConnectedToStorage;
  String get discoveredServers;
  String get manualInputAddress;
  String get serverIpAddress;
  String get serverIpHint;
  String get port;
  String get connect;
  String get connecting;
  String get connectionFailed;
  String get enterIpError;
  String get scanningLan;
  String get albums;
  String get noPhotosInAlbum;
  String get back;

  // ---------------------------------------------------------------------------
  // Upload screen
  // ---------------------------------------------------------------------------
  String get uploadTitle;
  String get notConnectedWarning;
  String get album;
  String get noAlbumsFound;
  String get startUpload;
  String get pause;
  String get resume;
  String get noPhotosInRange;
  String uploadSummary(int done, int total, int failed);

  // Upload screen — extra
  String get photoPermissionRequired;
  String get goToSettings;
  String get connectServerFirst;
  String get alreadyUploaded;
  String photoCount(int n);
  String get noPhotos;
  String get sortNewestFirst;
  String get sortOldestFirst;

  // ---------------------------------------------------------------------------
  // Cleanup screen
  // ---------------------------------------------------------------------------
  String get cleanupTitle;
  String get reset;
  String get backedUpPhotos;
  String get calculating;
  String get zeroFiles;
  String get zeroKbFreed;
  String filesCount(int n);
  String canBeFreed(String size);
  String get tapCalculate;
  String get calculate;
  String get cleanUp;
  String get cleanupComplete;
  String filesRemoved(int n);
  String sizeFreed(String size);
  String filesCouldNotDelete(int n);
  String get cloudReminderTitle;
  String get cloudReminderBody;
  String get errorPrefix;

  // ---------------------------------------------------------------------------
  // Album browser (desktop)
  // ---------------------------------------------------------------------------
  String get devices;
  String get noDevices;
  String get selectAnAlbum;
  String get noMedia;

  // ---------------------------------------------------------------------------
  // Settings screen (desktop)
  // ---------------------------------------------------------------------------
  String get settingsTitle;
  String get storagePath;
  String get storagePathDesc;
  String get browse;
  String get pathExists;
  String get pathNotExist;
  String get enterStoragePath;
  String get cancel;
  String get ok;
  String get storagePathSaved;
  String get invalidPath;

  // ---------------------------------------------------------------------------
  // Help screen — mobile
  // ---------------------------------------------------------------------------
  String get helpTitle;
  String get helpWhatTitle;
  String get helpWhatContent;
  String get helpPrereqTitle;
  String get helpPrereqStep1;
  String get helpPrereqStep2;
  String get helpPrereqStep3;
  String get helpStep1Title;
  String get helpStep1_1;
  String get helpStep1_2;
  String get helpStep1_3;
  String get helpStep2Title;
  String get helpStep2_1;
  String get helpStep2_2;
  String get helpStep2_3;
  String get helpStep2_4;
  String get helpStep3Title;
  String get helpStep3_1;
  String get helpStep3_2;
  String get helpStep3_3;
  String get helpStep3_4;
  String get helpCloudTitle;
  String get helpCloudContent;
  String get helpRestoreTitle;
  String get helpRestoreContent;
  String get helpNotesTitle;
  String get helpNote1;
  String get helpNote2;
  String get helpNote3;
  String get helpNote4;

  // ---------------------------------------------------------------------------
  // Help screen — desktop
  // ---------------------------------------------------------------------------
  String get helpDesktopWhatTitle;
  String get helpDesktopWhatContent;
  String get helpDesktopQuickStartTitle;
  String get helpDesktopQuickStart1;
  String get helpDesktopQuickStart2;
  String get helpDesktopQuickStart3;
  String get helpDesktopQuickStart4;
  String get helpDesktopQuickStart5;
  String get helpDesktopAlbumsTitle;
  String get helpDesktopAlbums1;
  String get helpDesktopAlbums2;
  String get helpDesktopAlbums3;
  String get helpDesktopAlbums4;
  String get helpDesktopDevicesTitle;
  String get helpDesktopDevicesContent;
  String get helpDesktopSettingsTitle;
  String get helpDesktopSettingsContent;
  String get helpDesktopStorageTitle;
  String get helpDesktopStorageContent;
  String get helpDesktopNotesTitle;
  String get helpDesktopNote1;
  String get helpDesktopNote2;
  String get helpDesktopNote3;
  String get helpDesktopNote4;
}

// ---------------------------------------------------------------------------
// Delegate
// ---------------------------------------------------------------------------

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'zh'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    final l = locale.languageCode == 'zh'
        ? AppLocalizationsZh()
        : AppLocalizationsEn();
    return SynchronousFuture<AppLocalizations>(l);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
