// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'Aria2Down';

  @override
  String get navTasks => 'Tarefas';

  @override
  String get navAdd => 'Novo';

  @override
  String get navSettings => 'Configurações';

  @override
  String get loadingAria2 => 'Starting aria2…';

  @override
  String get loadingRemoteAria2 => 'Connecting to remote aria2…';

  @override
  String get loadingSettings => 'Loading settings…';

  @override
  String get settingsTitle => 'Configurações';

  @override
  String get appearance => 'Aparência';

  @override
  String get theme => 'Tema';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Escuro';

  @override
  String get themeSeedColor => 'Accent color';

  @override
  String get themeSeedColorBody =>
      'Material 3 derives the full light/dark palette from this seed color. Tap a preset, leave on the default, or enter a custom hex.';

  @override
  String get themeSeedColorDefault => 'Default (brand)';

  @override
  String get themeSeedColorCustomTitle => 'Custom accent color';

  @override
  String get themeSeedColorCustomBody =>
      'Enter a hex color (#RRGGBB or #AARRGGBB).';

  @override
  String get themeSeedColorCustomInvalid =>
      'Invalid hex color. Use 6 or 8 hex digits.';

  @override
  String get language => 'Idioma';

  @override
  String get langSystem => 'Padrão do sistema';

  @override
  String get langEnglish => 'English';

  @override
  String get langChineseSimplified => '简体中文';

  @override
  String get langChineseTraditional => '繁體中文';

  @override
  String get langJapanese => '日本語';

  @override
  String get langKorean => '한국어';

  @override
  String get langSpanish => 'Español';

  @override
  String get langFrench => 'Français';

  @override
  String get langGerman => 'Deutsch';

  @override
  String get langRussian => 'Русский';

  @override
  String get langPortuguese => 'Português';

  @override
  String get langArabic => 'العربية';

  @override
  String get langVietnamese => 'Tiếng Việt';

  @override
  String get downloadDirectory => 'Default download folder';

  @override
  String get downloadDirectoryPick => 'Choose folder';

  @override
  String get downloadDirectoryClear => 'Use system default';

  @override
  String get save => 'Salvar';

  @override
  String get tasksTitle => 'Tarefas';

  @override
  String get tabActive => 'Ativas';

  @override
  String get tabWaiting => 'Aguardando';

  @override
  String get tabCompleted => 'Concluídas';

  @override
  String get tabStopped => 'Paradas';

  @override
  String get tabHistory => 'Histórico';

  @override
  String get emptyHistory => 'Ainda não há histórico local';

  @override
  String get searchTasks => 'Search tasks';

  @override
  String get searchTasksHint => 'Filter by name or GID';

  @override
  String get refreshTasks => 'Atualizar';

  @override
  String get addTaskFieldDownloadDir => 'Download to (this task)';

  @override
  String get addTaskFieldDownloadDirHint =>
      'Leave blank to use the default folder';

  @override
  String get pickDownloadDirTooltip => 'Pick a folder';

  @override
  String get askDownloadDirEachTimeTitle =>
      'Ask for the download folder each time';

  @override
  String get askDownloadDirEachTimeBody =>
      'When enabled, every new download opens a folder picker before being queued. Desktop platforms get the native picker; mobile platforms only see sandbox-writable folders since aria2 cannot write to SAF URIs.';

  @override
  String get downloadDirMobileSheetTitle => 'Pick a writable folder';

  @override
  String get downloadDirMobileSheetNote =>
      'aria2 can only write to paths inside the app sandbox on mobile. Pick a suggested folder or type a custom path you have already created.';

  @override
  String get downloadDirMobileSheetConfirm => 'Use this path';

  @override
  String get downloadDirAndroidExternalFiles => 'App external files';

  @override
  String get downloadDirAndroidAppDocuments => 'App internal documents';

  @override
  String get downloadDirIosDocuments => 'App Documents (visible in Files app)';

  @override
  String get downloadDirIosAppSupport => 'App Support (hidden)';

  @override
  String get downloadDirCandidateUse => 'Use';

  @override
  String get downloadDirCandidateUseSubdir => 'Use a subfolder';

  @override
  String get downloadDirSubdirHint => 'Subfolder name (e.g. Movies)';

  @override
  String get downloadDirRemovableOnUninstall =>
      'Cleared when the app is uninstalled.';

  @override
  String get downloadDirManualPathLabel => 'Custom path';

  @override
  String get downloadDirManualPathHint => '/sdcard/Download/aria2';

  @override
  String get historyClearTitle => 'Clear history';

  @override
  String get historyClearMessage =>
      'Removes saved finished tasks on this device. Does not affect the current aria2 queue.';

  @override
  String get historyClearConfirm => 'Clear';

  @override
  String get historyDeleteTooltip => 'Remove from history';

  @override
  String get historyDeleteTitle => 'Remove from history?';

  @override
  String get historyDeleteMessage =>
      'Removes this entry from the local history. Does not affect the aria2 queue. Files on disk are kept.';

  @override
  String get historyDeleteConfirm => 'Remove';

  @override
  String get historyDeleteSnack => 'Removed from history';

  @override
  String get mobilePathSheetTitle => 'Save path';

  @override
  String get mobilePathCopied => 'Path copied to clipboard';

  @override
  String get copyPath => 'Copy path';

  @override
  String get snackCopied => 'Copied';

  @override
  String get copyValue => 'Copy';

  @override
  String get taskDetailPieceProgress => 'Piece completion';

  @override
  String get taskDetailOverallProgress => 'Overall progress';

  @override
  String speedGlobal(String down, String up, int active, int waiting) {
    return '↓ $down  ↑ $up  active $active  waiting $waiting';
  }

  @override
  String speedGlobalExtended(
    String down,
    String up,
    int active,
    int waiting,
    int stopped,
  ) {
    return '↓ $down  ↑ $up  active $active  waiting $waiting  stopped $stopped';
  }

  @override
  String aria2Version(String version) {
    return 'aria2 $version';
  }

  @override
  String get wsConnected => 'WebSocket notifications connected';

  @override
  String get wsPolling => 'WebSocket unavailable; using periodic refresh';

  @override
  String get emptyActive => 'Sem downloads ativos';

  @override
  String get emptyWaiting => 'Sem tarefas aguardando';

  @override
  String get emptyCompleted => 'Sem downloads concluídos';

  @override
  String get emptyStopped => 'Sem tarefas paradas';

  @override
  String get statusPaused => 'Pausado';

  @override
  String get statusComplete => 'Concluído';

  @override
  String get statusError => 'Erro';

  @override
  String get statusRemoved => 'Removido';

  @override
  String get taskDetailHistorySnapshotBanner =>
      'Task is no longer in aria2; showing local history snapshot. Live fields (speed, peers, etc.) are unavailable.';

  @override
  String get taskDetailBackToList => 'Back to task list';

  @override
  String get libraryCapabilitiesDegradedTitle =>
      'Library engine running with limited capabilities';

  @override
  String libraryCapabilitiesDegradedBody(String missing) {
    return 'This libaria2 build is missing some patches: $missing. Stopped-task removal may silently no-op and waiting/stopped lists fall back to the Dart-side simulator. Rerun ./scripts/build_libaria2_<platform>.sh to refresh the prebuilt artifacts.';
  }

  @override
  String get libraryCapabilityRemoveDownloadResult => 'delete completed tasks';

  @override
  String get libraryCapabilityListReserved => 'enumerate waiting tasks';

  @override
  String get libraryCapabilityListDownloadResults => 'enumerate stopped tasks';

  @override
  String get libraryCapabilityDownloadHandleExt =>
      'BitTorrent top-level fields (numSeeders, etc.)';

  @override
  String get loadMoreStopped => 'Load more';

  @override
  String loadMoreStoppedWithCount(int loaded) {
    return 'Load more ($loaded loaded)';
  }

  @override
  String loadedAllStopped(int total) {
    return 'All stopped tasks loaded ($total)';
  }

  @override
  String get hintUrls =>
      'HTTP(S) / FTP / magnet links; separate with space or newline';

  @override
  String get addButton => 'Adicionar';

  @override
  String get snackAdded => 'Download added';

  @override
  String snackAddFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get snackInvalidUrl => 'No valid URLs in input';

  @override
  String get snackSaved => 'Settings saved';

  @override
  String get advancedOptions => 'Advanced…';

  @override
  String get userAgent => 'User-Agent';

  @override
  String get headersHint => 'HTTP headers, one per line: Name: Value';

  @override
  String get cookie => 'Cookie header value (optional)';

  @override
  String get speedLimitHint =>
      'Speed limit (aria2 max-download-limit), e.g. 2M or 500K';

  @override
  String get pickTorrent => 'Escolher .torrent';

  @override
  String get pickMetalink => 'Escolher Metalink';

  @override
  String get retry => 'Tentar de novo';

  @override
  String get openFolder => 'Abrir pasta';

  @override
  String get openFolderWebCopied =>
      'Copied the save path to the clipboard (browsers cannot open a local folder; path is from the aria2 server).';

  @override
  String get openFolderFailed => 'Could not open folder';

  @override
  String get openFolderMobileDirOnly =>
      'On mobile, opening only a folder in the file manager isn’t supported. Wait until a file exists, then open that file from the list.';

  @override
  String get openFileFailed =>
      'Could not open the file (invalid path, no app, or permission denied).';

  @override
  String get snackRetryQueued => 'Download re-queued';

  @override
  String get snackNothingToRetry => 'No links to retry for this task';

  @override
  String get torrentNote =>
      'Torrent/Metalink is sent to the local aria2 over RPC only.';

  @override
  String get dialogCancel => 'Cancelar';

  @override
  String get dialogConfirm => 'OK';

  @override
  String get torrentSelectDialogTitle => 'Choose files to download';

  @override
  String get torrentSelectDialogConfirm => 'Add';

  @override
  String get about => 'About';

  @override
  String get aboutDesc => 'Cross-platform download client powered by aria2.';

  @override
  String appVersionLabel(String version) {
    return 'Version $version';
  }

  @override
  String get folderPickerUnavailable =>
      'Folder picker is not available on this platform.';

  @override
  String get taskDetailTitle => 'Task details';

  @override
  String taskDetailLoadFailed(String error) {
    return 'Load failed: $error';
  }

  @override
  String get taskDetailTabOverview => 'Overview';

  @override
  String get taskDetailTabFiles => 'Files';

  @override
  String get taskDetailTabTorrent => 'Torrent';

  @override
  String get taskDetailFieldGid => 'GID';

  @override
  String get taskDetailFieldStatus => 'Status';

  @override
  String get taskDetailFieldDir => 'Directory';

  @override
  String get taskDetailFieldTotal => 'Total size';

  @override
  String get taskDetailFieldCompleted => 'Completed';

  @override
  String get taskDetailFieldUploadLength => 'Uploaded';

  @override
  String get taskDetailFieldDownloadSpeed => 'Download speed';

  @override
  String get taskDetailFieldUploadSpeed => 'Upload speed';

  @override
  String get taskDetailFieldConnections => 'Connections';

  @override
  String get taskDetailFieldPieces => 'Pieces';

  @override
  String get taskDetailFieldBitfield => 'Piece bitfield (hex)';

  @override
  String taskDetailPieceSummary(String count, String pieceSize) {
    return '$count × $pieceSize';
  }

  @override
  String get taskDetailFieldError => 'Error';

  @override
  String get taskDetailNoFiles => 'No file entries';

  @override
  String taskDetailFileProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String taskDetailFileProgressSelected(
    String done,
    String total,
    String selected,
  ) {
    return '$done / $total · selected=$selected';
  }

  @override
  String get taskDetailNotTorrent => 'This download is not a BitTorrent task.';

  @override
  String get taskDetailTorrentName => 'Torrent name';

  @override
  String get taskDetailTorrentMode => 'Mode';

  @override
  String get taskDetailAnnounceList => 'Trackers / announce';

  @override
  String taskDetailAnnounceTier(int tier) {
    return 'Tier $tier';
  }

  @override
  String get taskDetailBtMetricsTitle => 'Transfer & connectivity';

  @override
  String get taskDetailFieldInfoHash => 'Info hash';

  @override
  String get taskDetailFieldNumSeeders => 'Seeders (tracker-reported)';

  @override
  String get taskDetailFieldLocalSeeder => 'This client is seeding';

  @override
  String get taskDetailFieldBtConnections => 'Connections';

  @override
  String get taskDetailTrackerRpcNote =>
      'aria2 JSON-RPC does not expose per-tracker health; values below are task-level.';

  @override
  String get taskDetailBtRpcOptionsTitle => 'BitTorrent options (getOption)';

  @override
  String get taskDetailBtRpcOptionsNote =>
      'Effective values for this download in aria2.';

  @override
  String get taskDetailOptionEnableDht => 'DHT (IPv4)';

  @override
  String get taskDetailOptionEnableDht6 => 'DHT (IPv6)';

  @override
  String get taskDetailOptionBtEnableLpd => 'Local peer discovery (LPD)';

  @override
  String get taskDetailBoolYes => 'Yes';

  @override
  String get taskDetailBoolNo => 'No';

  @override
  String get taskDetailNoAnnounces => 'No announce list';

  @override
  String taskDetailPeersTitle(int count) {
    return 'Peers ($count)';
  }

  @override
  String get taskDetailPeersEmpty =>
      'No peer data (not connected yet or task finished).';

  @override
  String get taskDetailPeerDown => 'Down';

  @override
  String get taskDetailPeerUp => 'Up';

  @override
  String get taskDetailSelectFilesHint =>
      'Choose files to download, then apply to aria2 (waiting / paused / active tasks).';

  @override
  String get taskDetailApplyFileSelection => 'Apply file selection';

  @override
  String taskDetailFileSelectionApplyFailed(String error) {
    return 'Apply failed: $error';
  }

  @override
  String get taskDetailNeedOneFileSelected =>
      'Keep at least one file selected.';

  @override
  String get taskDetailFileSelectionSaved => 'File selection applied.';

  @override
  String get settingsConnection => 'Conexão';

  @override
  String get connectionLocal => 'aria2 local';

  @override
  String get connectionRemote => 'RPC remoto';

  @override
  String get settingsEngine => 'Local engine';

  @override
  String get engineLibrary => 'Embedded library (libaria2)';

  @override
  String get engineLibraryDesc =>
      'Runs aria2 in-process via FFI on every supported platform. The aria2c subprocess engine was removed in ADR-010 — use Remote RPC if you need to delegate to an external aria2c.';

  @override
  String engineCurrent(String engine) {
    return 'Active engine: $engine';
  }

  @override
  String get engineLibraryShort => 'library';

  @override
  String get engineRemoteShort => 'remote';

  @override
  String get remoteRpcEndpoint => 'RPC endpoint';

  @override
  String get remoteRpcEndpointHint =>
      'e.g. 127.0.0.1:6800 or http://nas:6800/jsonrpc';

  @override
  String get remoteRpcSecret => 'RPC secret (token)';

  @override
  String get remoteModeHint =>
      'Remote mode does not start a local process. Ensure aria2 RPC is enabled and the secret matches.';

  @override
  String get settingsDownloadTuning => 'Download tuning (local aria2.conf)';

  @override
  String get settingsOptionalHint => 'Leave empty for aria2 default';

  @override
  String get maxConcurrentDownloads => 'Max concurrent downloads';

  @override
  String get maxConnectionPerServer => 'Max connections per server';

  @override
  String get globalDownloadLimit => 'Global download limit';

  @override
  String get globalUploadLimit => 'Global upload limit';

  @override
  String get settingsTuningLocalOnly =>
      'These options apply only in local aria2 mode (written to aria2.conf).';

  @override
  String get settingsDesktop => 'Desktop';

  @override
  String get closeToTray => 'Close to system tray';

  @override
  String get closeToTrayDesc =>
      'The close button hides the window; use Quit in the tray menu to exit.';

  @override
  String get minimizeToTray => 'Minimize to tray';

  @override
  String get minimizeToTrayDesc =>
      'Hide the window when minimized (otherwise normal minimize).';

  @override
  String get launchAtStartup => 'Launch at login';

  @override
  String get launchAtStartupDesc =>
      'Start Aria2Down when you sign in (OS permissions may apply).';

  @override
  String get settingsBackup => 'Backup & restore';

  @override
  String get settingsExport => 'Export settings';

  @override
  String get settingsImport => 'Import settings';

  @override
  String get settingsExportCopied => 'Settings JSON copied to clipboard';

  @override
  String settingsExportSaved(String path) {
    return 'Settings saved to $path';
  }

  @override
  String get settingsImportApplied =>
      'Settings loaded. Tap Save to persist, or edit first.';

  @override
  String settingsImportFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get trayShowWindow => 'Show window';

  @override
  String get trayQuit => 'Quit';

  @override
  String get trayToolTip => 'Aria2Down — click to show';

  @override
  String get trayNewTask => 'New download…';

  @override
  String get trayPauseAll => 'Pause all';

  @override
  String get trayResumeAll => 'Resume all';

  @override
  String get trayOpenDownloads => 'Open downloads folder';

  @override
  String trayToolTipStats(String down, String up, int active, int waiting) {
    return 'Aria2Down\n↓ $down  ↑ $up\nactive $active · waiting $waiting';
  }

  @override
  String get trayToolTipOffline => 'Aria2Down\nDisconnected — click to retry';

  @override
  String get startMinimized => 'Start hidden in tray';

  @override
  String get startMinimizedDesc =>
      'Launch directly into the system tray instead of showing the main window. Pairs well with “Launch at login”.';

  @override
  String get keepAliveInBackground => 'Keep downloads alive in background';

  @override
  String get keepAliveInBackgroundDesc =>
      'Android: persistent foreground service notification so the OS keeps the daemon running. iOS: request limited background execution time. When off, downloads may be paused once the app is suspended.';

  @override
  String get keepAliveTitle => 'Aria2Down is downloading in the background';

  @override
  String get notifPauseAllDone => 'Requested pause-all';

  @override
  String get notifResumeAllDone => 'Requested resume-all';

  @override
  String get tasksBatchMenu => 'Batch actions';

  @override
  String get batchPauseAll => 'Pause all';

  @override
  String get batchForcePauseAll => 'Force pause all';

  @override
  String get batchExportTasks => 'Export task snapshot';

  @override
  String get batchExportTasksDone => 'Task snapshot copied to clipboard';

  @override
  String get batchUnpauseAll => 'Resume all';

  @override
  String get settingsDiagnostics => 'Diagnostics';

  @override
  String get aria2LogTitle => 'aria2 log';

  @override
  String get aria2LogSubtitle => 'Last lines from the local aria2 log file';

  @override
  String get aria2LogEmpty => 'Log file is empty or not created yet.';

  @override
  String get batchPurgeStopped => 'Purge stopped results';

  @override
  String get snackBatchDone => 'Batch action completed';

  @override
  String get pasteFromClipboard => 'Colar da área de transferência';

  @override
  String get clipboardEmpty => 'Clipboard is empty';

  @override
  String get applyRuntimeLimits => 'Apply to running aria2';

  @override
  String get applyRuntimeLimitsHint =>
      'Updates global limits without restart (local or remote).';

  @override
  String get applyRuntimeLimitsDone => 'Running options updated';

  @override
  String get applyRuntimeLimitsEmpty =>
      'Enter at least one limit or concurrency value';

  @override
  String get aboutTitle => 'About Aria2Down';

  @override
  String get aboutOpenDetail => 'Version, license, and links';

  @override
  String get aboutPoweredBy => 'Download engine';

  @override
  String get aboutLicense => 'License';

  @override
  String get aboutLicenseBody =>
      'Released under GPLv2+, compatible with aria2.';

  @override
  String get aboutLicenseLink => 'GNU GPLv2 full text';

  @override
  String get platformHintMessage =>
      'Downloads may pause when the app is in the background. Keep the app open or use Remote RPC to a server that stays online.';

  @override
  String get platformHintOpenSettings => 'Open settings';

  @override
  String get platformHintDismiss => 'Don\'t show again';

  @override
  String get mobileSettingsCardTitle => 'Mobile tips';

  @override
  String get mobileSettingsCardBody =>
      'Local mode downloads inside the app. Switch to Remote RPC to use aria2 on a NAS or PC. Background downloads may pause when the screen is locked.';

  @override
  String get welcomeUseLocal => 'Use local download';

  @override
  String get welcomeSetupRemote => 'Set up remote RPC';

  @override
  String get daemonErrorTitle => 'Cannot connect to aria2';

  @override
  String get daemonErrorWebLocal =>
      'The browser cannot start a local aria2 process. Use Remote RPC in Settings.';

  @override
  String get daemonErrorRetry => 'Retry';

  @override
  String get daemonErrorSwitchRemote => 'Switch to remote RPC';

  @override
  String get welcomeRemoteTitle => 'Welcome to Aria2Down';

  @override
  String get welcomeRemoteBody =>
      'Download on this device with the built-in engine, or connect to aria2 on a NAS or PC via Remote RPC in Settings.';

  @override
  String get snackAllDuplicates => 'These links are already in the queue';

  @override
  String snackAddedWithSkipped(int added, int skipped) {
    return 'Added $added; skipped $skipped duplicate(s)';
  }

  @override
  String get batchRemoveStopped => 'Remove all stopped tasks';

  @override
  String get delete => 'Excluir';

  @override
  String get swipeDeleteTitle => 'Remove task?';

  @override
  String get swipeDeleteMessage =>
      'This removes the task from aria2 (files on disk are kept unless you enabled delete-on-remove).';

  @override
  String get remoteTestConnection => 'Test connection';

  @override
  String remoteTestOk(String version, String ws) {
    return 'Connected — aria2 $version, WebSocket: $ws';
  }

  @override
  String remoteTestFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String get aboutRpcInfo => 'Current RPC';

  @override
  String get aboutRpcSecretHint =>
      'RPC token (for extensions / remote clients on this machine):';

  @override
  String get taskShare => 'Copy share text';

  @override
  String get aria2GlobalOptionsTitle => 'aria2 global options';

  @override
  String get aria2GlobalOptionsSubtitle => 'Read-only list from running aria2';

  @override
  String get copyRpcConfigTitle => 'Copy RPC config for extension';

  @override
  String get copyRpcConfigSubtitle =>
      'JSON for Chrome extension options (uses your Remote RPC endpoint + secret)';

  @override
  String get copyRpcConfigDone => 'RPC config copied to clipboard';

  @override
  String get copyRpcConfigUnavailable =>
      'Start local aria2 once to generate rpc.secret';

  @override
  String get taskActionPause => 'Pause';

  @override
  String get taskActionResume => 'Resume';

  @override
  String get taskActionForcePause => 'Force pause';

  @override
  String get settingsWebRemoteOnly => 'Web builds only support Remote RPC.';

  @override
  String get connectionStatusTitle => 'Current connection';

  @override
  String get connectionStatusLoading => 'Connecting…';

  @override
  String get connectionStatusOffline => 'Not connected';

  @override
  String connectionStatusWs(String status) {
    return 'WebSocket notifications: $status';
  }

  @override
  String get desktopShortcutRefresh => 'Refresh task list';

  @override
  String get desktopShortcutSettings => 'Open settings';

  @override
  String get pasteAndAdd => 'Colar e adicionar';

  @override
  String snackAddedCount(int count) {
    return 'Added $count task(s)';
  }

  @override
  String get copyTaskUris => 'Copy all URIs';

  @override
  String get settingsDangerZone => 'Advanced / danger zone';

  @override
  String get shutdownAria2 => 'Shut down aria2';

  @override
  String get shutdownAria2Title => 'Shut down aria2?';

  @override
  String get shutdownAria2Message =>
      'Gracefully stops the aria2 daemon. Active downloads will stop. You can reconnect later.';

  @override
  String get shutdownAria2Confirm => 'Shut down';

  @override
  String get shutdownAria2Done => 'aria2 shut down';

  @override
  String get resetSettings => 'Reset to defaults';

  @override
  String get resetSettingsTitle => 'Reset settings?';

  @override
  String get resetSettingsMessage =>
      'Clears all app settings (task history file is kept). aria2 will reconnect.';

  @override
  String get resetSettingsConfirm => 'Reset';

  @override
  String get resetSettingsDone => 'Settings reset';

  @override
  String get copyAddTaskLink => 'Copy in-app add link';

  @override
  String get taskContextViewDetail => 'View details';

  @override
  String get desktopShortcutAdd => 'New download task';

  @override
  String get aboutDesktopShortcuts => 'Keyboard shortcuts (desktop)';

  @override
  String get globalOptionsSearchHint => 'Search options…';

  @override
  String get copyDeepLinkExampleTitle => 'Copy example add-task link';

  @override
  String get copyDeepLinkExampleSubtitle =>
      'In-app path like /add?uri=… — see docs/DEEPLINKS.md';

  @override
  String get copyDeepLinkExampleDone => 'Example deep link copied';

  @override
  String get rpcErrorConnection =>
      'Cannot reach aria2 RPC. Check that aria2 is running and Settings → RPC address is correct.';

  @override
  String get rpcErrorUnauthorized =>
      'RPC rejected the request. Check the token / secret in Settings.';

  @override
  String rpcErrorGeneric(String error) {
    return 'Request failed: $error';
  }

  @override
  String get copyRpcEndpoint => 'Copy RPC URL';

  @override
  String get batchExportHistory => 'Export history (JSON)';

  @override
  String get batchExportHistoryDone => 'Task history copied to clipboard';

  @override
  String get batchClearStoppedResults => 'Clear stopped list (keep files)';

  @override
  String get pasteAndQueue => 'Paste and queue';

  @override
  String get batchImportHistory => 'Import history from clipboard';

  @override
  String historyImportDone(int count) {
    return 'Imported $count history record(s)';
  }

  @override
  String historyImportFailed(String error) {
    return 'History import failed: $error';
  }

  @override
  String get copyGlobalOptions => 'Copy all options';

  @override
  String get copyGlobalOptionsDone => 'Global options copied to clipboard';

  @override
  String get aboutBrowserExtension => 'Browser extension';

  @override
  String get aboutBrowserExtensionHint =>
      'See extensions/README.md in the repository';

  @override
  String get aria2LogSearchHint => 'Search log lines…';

  @override
  String get aria2LogNoMatch => 'No log lines match your search.';
}
