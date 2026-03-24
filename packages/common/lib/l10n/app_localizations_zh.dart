import 'app_localizations.dart';

class AppLocalizationsZh extends AppLocalizations {
  // Common / Navigation
  @override String get appTitle => '照片存储清理器';
  @override String get navBrowse => '浏览';
  @override String get navUpload => '上传';
  @override String get navCleanUp => '清理';
  @override String get navHelp => '帮助';
  @override String get navAlbums => '相册';
  @override String get navDevices => '设备';
  @override String get navSettings => '设置';

  // Server address bar
  @override String get serverAddress => '服务器地址：';
  @override String get copied => '已复制';
  @override String get copy => '复制';

  // Browse screen
  @override String get browseTitle => '浏览照片';
  @override String get selectToRestore => '选择要恢复的照片';
  @override String get restorePhotos => '恢复照片';
  @override String get exitRestoreMode => '退出恢复模式';
  @override String get notConnectedToStorage => '未连接到存储服务器';
  @override String get discoveredServers => '发现的服务器：';
  @override String get manualInputAddress => '手动输入服务器地址';
  @override String get serverIpAddress => '服务器 IP 地址';
  @override String get serverIpHint => '例如：192.168.1.100';
  @override String get port => '端口';
  @override String get connect => '连接';
  @override String get connecting => '连接中…';
  @override String get connectionFailed => '连接失败，请检查 IP 和端口';
  @override String get enterIpError => '请输入服务器 IP 地址';
  @override String get scanningLan => '正在扫描局域网…';
  @override String get albums => '相册';
  @override String get noPhotosInAlbum => '该相册没有照片';
  @override String get back => '相册';

  // Upload screen
  @override String get uploadTitle => '上传照片';
  @override String get notConnectedWarning => '未连接到服务器，请先连接。';
  @override String get album => '相册';
  @override String get noAlbumsFound => '未找到相册，请授予相册访问权限。';
  @override String get startUpload => '开始上传';
  @override String get pause => '暂停';
  @override String get resume => '继续';
  @override String get noPhotosInRange => '所选范围内没有照片。';
  @override String uploadSummary(int done, int total, int failed) =>
      '完成：$done/$total 已上传${failed > 0 ? '，$failed 失败' : ''}。';

  // Cleanup screen
  @override String get cleanupTitle => '清理照片';
  @override String get reset => '重置';
  @override String get backedUpPhotos => '已备份到服务器的本地照片';
  @override String get calculating => '计算中…';
  @override String get zeroFiles => '0 个文件';
  @override String get zeroKbFreed => '可释放 0 KB';
  @override String filesCount(int n) => '$n 个文件';
  @override String canBeFreed(String size) => '可释放 $size';
  @override String get tapCalculate => '点击「计算」查看可清理的文件。';
  @override String get calculate => '计算';
  @override String get cleanUp => '清理';
  @override String get cleanupComplete => '清理完成';
  @override String filesRemoved(int n) => '已删除 $n 个文件';
  @override String sizeFreed(String size) => '已释放 $size';
  @override String filesCouldNotDelete(int n) => '$n 个文件无法删除';
  @override String get cloudReminderTitle => '云端备份';
  @override String get cloudReminderBody =>
      '本地照片已删除。如需同时清理云端备份，请前往 Google Photos → 释放设备存储空间，或在 iPhone 的 iCloud 设置中管理存储。';
  @override String get errorPrefix => '错误：';

  // Album browser (desktop)
  @override String get devices => '设备';
  @override String get noDevices => '暂无设备';
  @override String get selectAnAlbum => '请选择相册';
  @override String get noMedia => '暂无照片';

  // Settings screen (desktop)
  @override String get settingsTitle => '设置';
  @override String get storagePath => '存储路径';
  @override String get storagePathDesc => '选择上传照片的存储文件夹。';
  @override String get browse => '浏览';
  @override String get pathExists => '路径存在且可访问';
  @override String get pathNotExist => '路径不存在';
  @override String get enterStoragePath => '输入存储路径';
  @override String get cancel => '取消';
  @override String get ok => '确定';
  @override String get storagePathSaved => '存储路径已保存。';
  @override String get invalidPath => '无效路径';

  // Help — mobile
  @override String get helpTitle => '使用说明';
  @override String get helpWhatTitle => '这是什么应用？';
  @override String get helpWhatContent =>
      '本应用可将手机照片备份到局域网内的 Mac/PC 存储服务器，备份完成后可安全删除手机本地副本，释放存储空间。';
  @override String get helpPrereqTitle => '使用前准备';
  @override String get helpPrereqStep1 => '在 Mac/PC 上启动 Photo Storage Server 桌面应用';
  @override String get helpPrereqStep2 => '确保手机与电脑连接在同一 Wi-Fi 网络';
  @override String get helpPrereqStep3 => '记录桌面端顶部显示的服务器地址（如 192.168.1.x:8765）';
  @override String get helpStep1Title => '第一步：连接服务器';
  @override String get helpStep1_1 => '打开底部导航的「浏览」页面';
  @override String get helpStep1_2 => '输入桌面端显示的 IP 地址和端口（默认 8765）';
  @override String get helpStep1_3 => '点击「连接」，状态变为绿色即连接成功';
  @override String get helpStep2Title => '第二步：上传照片';
  @override String get helpStep2_1 => '切换到「上传」页面';
  @override String get helpStep2_2 => '选择要备份的相册和日期范围';
  @override String get helpStep2_3 => '点击「开始上传」';
  @override String get helpStep2_4 => '上传过程中可暂停/继续，关闭页面不会中断';
  @override String get helpStep3Title => '第三步：清理本地照片';
  @override String get helpStep3_1 => '切换到「清理」页面';
  @override String get helpStep3_2 => '点击「计算」查看可释放空间';
  @override String get helpStep3_3 => '确认无误后点击「清理」';
  @override String get helpStep3_4 => 'Android 会弹出一次系统确认框，确认后批量删除';
  @override String get helpCloudTitle => '关于云端备份（Google Photos / iCloud）';
  @override String get helpCloudContent =>
      '本应用只删除手机本地副本，不会影响 Google Photos 或 iCloud 中的云端备份。\n\n'
      '如需同时清理云端内容：\n'
      '• Android：打开 Google Photos → 设置 → 释放设备存储空间\n'
      '• iPhone：设置 → Apple ID → iCloud → 照片，手动管理';
  @override String get helpRestoreTitle => '如何恢复照片？';
  @override String get helpRestoreContent =>
      '在「浏览」页面连接服务器后，可浏览已备份的照片。点击照片可查看原图，后续版本将支持下载恢复到手机相册。';
  @override String get helpNotesTitle => '注意事项';
  @override String get helpNote1 => '删除前请确认照片已成功上传到服务器';
  @override String get helpNote2 => '建议先在桌面端浏览确认照片完整';
  @override String get helpNote3 => '删除操作不可撤销（本地副本），请谨慎操作';
  @override String get helpNote4 => '保持 Wi-Fi 连接稳定以确保上传完整';

  // Help — desktop
  @override String get helpDesktopWhatTitle => '这是什么应用？';
  @override String get helpDesktopWhatContent =>
      'Photo Storage Server 是一个运行在 Mac/PC 上的局域网照片存储服务器。'
      '配合手机端应用，可将手机照片备份到本机，释放手机存储空间，同时保留完整原图。';
  @override String get helpDesktopQuickStartTitle => '快速开始';
  @override String get helpDesktopQuickStart1 => '启动本应用，顶部会显示服务器地址（如 192.168.1.x:8765）';
  @override String get helpDesktopQuickStart2 => '在手机上安装并打开 Photo Storage Cleaner 移动端应用';
  @override String get helpDesktopQuickStart3 => '确保手机与电脑在同一 Wi-Fi 网络下';
  @override String get helpDesktopQuickStart4 => '在手机端输入上方显示的地址进行连接';
  @override String get helpDesktopQuickStart5 => '连接成功后即可从手机端上传照片';
  @override String get helpDesktopAlbumsTitle => '相册 — 浏览照片';
  @override String get helpDesktopAlbums1 => '左侧选择设备，右侧选择相册';
  @override String get helpDesktopAlbums2 => '照片以缩略图网格展示，点击可查看原图';
  @override String get helpDesktopAlbums3 => '支持按日期范围筛选';
  @override String get helpDesktopAlbums4 => '缩略图在后台自动生成，首次加载需要一点时间';
  @override String get helpDesktopDevicesTitle => '设备 — 设备管理';
  @override String get helpDesktopDevicesContent =>
      '查看所有曾经连接过的手机设备，以及每台设备的上传记录和存储占用情况。';
  @override String get helpDesktopSettingsTitle => '设置';
  @override String get helpDesktopSettingsContent =>
      '配置存储路径、服务端口等参数。修改后需要重启应用生效。';
  @override String get helpDesktopStorageTitle => '照片存储位置';
  @override String get helpDesktopStorageContent =>
      '照片默认存储在系统 Documents 目录下，按设备 IP 和相册名分文件夹存放。\n\n'
      '路径格式：Documents/{设备IP:端口}/{相册名}/{文件名}\n\n'
      '缩略图缓存在 Application Support 目录，不占用 Documents 空间。';
  @override String get helpDesktopNotesTitle => '注意事项';
  @override String get helpDesktopNote1 => '上传过程中请保持应用运行，不要让 Mac 进入睡眠';
  @override String get helpDesktopNote2 => '建议在浏览页面确认照片完整后，再让手机端执行清理';
  @override String get helpDesktopNote3 => '删除手机本地照片后，服务器上的备份不受影响';
  @override String get helpDesktopNote4 => '如需迁移存储位置，请在设置中修改路径后重建索引';
}
