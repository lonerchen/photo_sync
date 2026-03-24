import 'app_localizations.dart';

class AppLocalizationsEn extends AppLocalizations {
  // Common / Navigation
  @override String get appTitle => 'Photo Storage Cleaner';
  @override String get navBrowse => 'Browse';
  @override String get navUpload => 'Upload';
  @override String get navCleanUp => 'Clean Up';
  @override String get navHelp => 'Help';
  @override String get navAlbums => 'Albums';
  @override String get navDevices => 'Devices';
  @override String get navSettings => 'Settings';

  // Server address bar
  @override String get serverAddress => 'Server address:';
  @override String get copied => 'Copied';
  @override String get copy => 'Copy';

  // Browse screen
  @override String get browseTitle => 'Browse Photos';
  @override String get selectToRestore => 'Select to Restore';
  @override String get restorePhotos => 'Restore photos';
  @override String get exitRestoreMode => 'Exit restore mode';
  @override String get notConnectedToStorage => 'Not connected to storage';
  @override String get discoveredServers => 'Discovered servers:';
  @override String get manualInputAddress => 'Enter server address manually';
  @override String get serverIpAddress => 'Server IP address';
  @override String get serverIpHint => 'e.g. 192.168.1.100';
  @override String get port => 'Port';
  @override String get connect => 'Connect';
  @override String get connecting => 'Connecting…';
  @override String get connectionFailed => 'Connection failed. Check IP and port.';
  @override String get enterIpError => 'Please enter the server IP address';
  @override String get scanningLan => 'Scanning local network…';
  @override String get albums => 'Albums';
  @override String get noPhotosInAlbum => 'No photos in this album';
  @override String get back => 'Albums';

  // Upload screen
  @override String get uploadTitle => 'Upload Photos';
  @override String get notConnectedWarning => 'Not connected to a server. Please connect first.';
  @override String get album => 'Album';
  @override String get noAlbumsFound => 'No albums found. Grant photo library permission.';
  @override String get startUpload => 'Start Upload';
  @override String get pause => 'Pause';
  @override String get resume => 'Resume';
  @override String get noPhotosInRange => 'No photos found for the selected range.';
  @override String uploadSummary(int done, int total, int failed) =>
      'Done: $done/$total uploaded${failed > 0 ? ', $failed failed' : ''}.';

  // Cleanup screen
  @override String get cleanupTitle => 'Clean Up Photos';
  @override String get reset => 'Reset';
  @override String get backedUpPhotos => 'Backed-up photos on this device';
  @override String get calculating => 'Calculating…';
  @override String get zeroFiles => '0 files';
  @override String get zeroKbFreed => '0 KB can be freed';
  @override String filesCount(int n) => '$n file${n == 1 ? '' : 's'}';
  @override String canBeFreed(String size) => '$size can be freed';
  @override String get tapCalculate => 'Tap "Calculate" to check eligible files.';
  @override String get calculate => 'Calculate';
  @override String get cleanUp => 'Clean Up';
  @override String get cleanupComplete => 'Cleanup complete';
  @override String filesRemoved(int n) => '$n file${n == 1 ? '' : 's'} removed';
  @override String sizeFreed(String size) => '$size freed';
  @override String filesCouldNotDelete(int n) =>
      '$n file${n == 1 ? '' : 's'} could not be deleted';
  @override String get cloudReminderTitle => 'Cloud backup';
  @override String get cloudReminderBody =>
      'Local photos deleted. To also clean cloud backups, go to Google Photos → Free up device storage, or manage iCloud storage in iPhone Settings.';
  @override String get errorPrefix => 'Error: ';

  // Album browser (desktop)
  @override String get devices => 'Devices';
  @override String get noDevices => 'No devices';
  @override String get selectAnAlbum => 'Select an album';
  @override String get noMedia => 'No media';

  // Settings screen (desktop)
  @override String get settingsTitle => 'Settings';
  @override String get storagePath => 'Storage Path';
  @override String get storagePathDesc => 'Choose the folder where uploaded photos will be stored.';
  @override String get browse => 'Browse';
  @override String get pathExists => 'Path exists and is accessible';
  @override String get pathNotExist => 'Path does not exist';
  @override String get enterStoragePath => 'Enter Storage Path';
  @override String get cancel => 'Cancel';
  @override String get ok => 'OK';
  @override String get storagePathSaved => 'Storage path saved.';
  @override String get invalidPath => 'Invalid path';

  // Help — mobile
  @override String get helpTitle => 'Help';
  @override String get helpWhatTitle => 'What is this app?';
  @override String get helpWhatContent =>
      'This app backs up your phone photos to a Mac/PC storage server on your local network. Once backed up, you can safely delete local copies to free up storage.';
  @override String get helpPrereqTitle => 'Before you start';
  @override String get helpPrereqStep1 => 'Launch Photo Storage Server on your Mac/PC';
  @override String get helpPrereqStep2 => 'Make sure your phone and computer are on the same Wi-Fi';
  @override String get helpPrereqStep3 => 'Note the server address shown at the top of the desktop app (e.g. 192.168.1.x:8765)';
  @override String get helpStep1Title => 'Step 1: Connect to server';
  @override String get helpStep1_1 => 'Open the "Browse" tab';
  @override String get helpStep1_2 => 'Enter the IP address and port (default 8765)';
  @override String get helpStep1_3 => 'Tap "Connect" — green status means connected';
  @override String get helpStep2Title => 'Step 2: Upload photos';
  @override String get helpStep2_1 => 'Switch to the "Upload" tab';
  @override String get helpStep2_2 => 'Select an album and date range';
  @override String get helpStep2_3 => 'Tap "Start Upload"';
  @override String get helpStep2_4 => 'You can pause/resume; closing the screen won\'t interrupt the upload';
  @override String get helpStep3Title => 'Step 3: Clean up local photos';
  @override String get helpStep3_1 => 'Switch to the "Clean Up" tab';
  @override String get helpStep3_2 => 'Tap "Calculate" to see how much space can be freed';
  @override String get helpStep3_3 => 'Tap "Clean Up" to delete local copies';
  @override String get helpStep3_4 => 'Android shows one system confirmation dialog for batch deletion';
  @override String get helpCloudTitle => 'Cloud backups (Google Photos / iCloud)';
  @override String get helpCloudContent =>
      'This app only deletes local copies — Google Photos and iCloud backups are not affected.\n\n'
      'To also clean cloud content:\n'
      '• Android: Google Photos → Settings → Free up device storage\n'
      '• iPhone: Settings → Apple ID → iCloud → Photos';
  @override String get helpRestoreTitle => 'How to restore photos?';
  @override String get helpRestoreContent =>
      'Connect to the server in the "Browse" tab to view backed-up photos. Tap a photo to view the original. Download/restore to camera roll will be supported in a future version.';
  @override String get helpNotesTitle => 'Important notes';
  @override String get helpNote1 => 'Confirm photos are fully uploaded before deleting';
  @override String get helpNote2 => 'Browse on the desktop app first to verify completeness';
  @override String get helpNote3 => 'Deletion of local copies is irreversible — proceed carefully';
  @override String get helpNote4 => 'Keep Wi-Fi stable during upload';

  // Help — desktop
  @override String get helpDesktopWhatTitle => 'What is this app?';
  @override String get helpDesktopWhatContent =>
      'Photo Storage Server runs on your Mac/PC as a local network photo storage server. Paired with the mobile app, it backs up phone photos to your computer while keeping full-resolution originals.';
  @override String get helpDesktopQuickStartTitle => 'Quick start';
  @override String get helpDesktopQuickStart1 => 'Launch this app — the server address is shown at the top (e.g. 192.168.1.x:8765)';
  @override String get helpDesktopQuickStart2 => 'Install and open Photo Storage Cleaner on your phone';
  @override String get helpDesktopQuickStart3 => 'Make sure phone and computer are on the same Wi-Fi';
  @override String get helpDesktopQuickStart4 => 'Enter the address shown above in the mobile app';
  @override String get helpDesktopQuickStart5 => 'Once connected, upload photos from the mobile app';
  @override String get helpDesktopAlbumsTitle => 'Albums — browse photos';
  @override String get helpDesktopAlbums1 => 'Select a device on the left, then an album';
  @override String get helpDesktopAlbums2 => 'Photos are shown as thumbnails — click to view full size';
  @override String get helpDesktopAlbums3 => 'Filter by date range';
  @override String get helpDesktopAlbums4 => 'Thumbnails are generated in the background — first load may take a moment';
  @override String get helpDesktopDevicesTitle => 'Devices — device management';
  @override String get helpDesktopDevicesContent =>
      'View all phones that have connected, along with their upload history and storage usage.';
  @override String get helpDesktopSettingsTitle => 'Settings';
  @override String get helpDesktopSettingsContent =>
      'Configure storage path and server port. Changes take effect after restarting the app.';
  @override String get helpDesktopStorageTitle => 'Photo storage location';
  @override String get helpDesktopStorageContent =>
      'Photos are stored in the system Documents folder, organized by device IP and album name.\n\n'
      'Path format: Documents/{device IP:port}/{album}/{filename}\n\n'
      'Thumbnail cache is in Application Support and does not count against Documents space.';
  @override String get helpDesktopNotesTitle => 'Important notes';
  @override String get helpDesktopNote1 => 'Keep the app running during upload — don\'t let your Mac sleep';
  @override String get helpDesktopNote2 => 'Verify photos in the Albums view before asking the mobile app to clean up';
  @override String get helpDesktopNote3 => 'Deleting local phone photos does not affect server backups';
  @override String get helpDesktopNote4 => 'To move storage, change the path in Settings then rebuild the index';
}
