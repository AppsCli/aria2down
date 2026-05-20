import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'aria2down'**
  String get appTitle;

  /// No description provided for @navTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get navTasks;

  /// No description provided for @navAdd.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get navAdd;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @loadingAria2.
  ///
  /// In en, this message translates to:
  /// **'Starting aria2…'**
  String get loadingAria2;

  /// No description provided for @loadingRemoteAria2.
  ///
  /// In en, this message translates to:
  /// **'Connecting to remote aria2…'**
  String get loadingRemoteAria2;

  /// No description provided for @loadingSettings.
  ///
  /// In en, this message translates to:
  /// **'Loading settings…'**
  String get loadingSettings;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @langSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get langSystem;

  /// No description provided for @langEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// No description provided for @langChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get langChinese;

  /// No description provided for @downloadDirectory.
  ///
  /// In en, this message translates to:
  /// **'Default download folder'**
  String get downloadDirectory;

  /// No description provided for @downloadDirectoryPick.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get downloadDirectoryPick;

  /// No description provided for @downloadDirectoryClear.
  ///
  /// In en, this message translates to:
  /// **'Use system default'**
  String get downloadDirectoryClear;

  /// No description provided for @aria2BinaryPath.
  ///
  /// In en, this message translates to:
  /// **'aria2c path (optional)'**
  String get aria2BinaryPath;

  /// No description provided for @aria2BinaryHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to search PATH'**
  String get aria2BinaryHint;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @restartAria2Hint.
  ///
  /// In en, this message translates to:
  /// **'aria2 will restart to apply path changes.'**
  String get restartAria2Hint;

  /// No description provided for @tasksTitle.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tasksTitle;

  /// No description provided for @tabActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get tabActive;

  /// No description provided for @tabWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get tabWaiting;

  /// No description provided for @tabStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get tabStopped;

  /// No description provided for @tabHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get tabHistory;

  /// No description provided for @emptyHistory.
  ///
  /// In en, this message translates to:
  /// **'No local history yet'**
  String get emptyHistory;

  /// No description provided for @searchTasks.
  ///
  /// In en, this message translates to:
  /// **'Search tasks'**
  String get searchTasks;

  /// No description provided for @searchTasksHint.
  ///
  /// In en, this message translates to:
  /// **'Filter by name or GID'**
  String get searchTasksHint;

  /// No description provided for @refreshTasks.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshTasks;

  /// No description provided for @historyClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get historyClearTitle;

  /// No description provided for @historyClearMessage.
  ///
  /// In en, this message translates to:
  /// **'Removes saved finished tasks on this device. Does not affect the current aria2 queue.'**
  String get historyClearMessage;

  /// No description provided for @historyClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get historyClearConfirm;

  /// No description provided for @mobilePathSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Save path'**
  String get mobilePathSheetTitle;

  /// No description provided for @mobilePathCopied.
  ///
  /// In en, this message translates to:
  /// **'Path copied to clipboard'**
  String get mobilePathCopied;

  /// No description provided for @copyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get copyPath;

  /// No description provided for @snackCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get snackCopied;

  /// No description provided for @copyValue.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyValue;

  /// No description provided for @taskDetailPieceProgress.
  ///
  /// In en, this message translates to:
  /// **'Piece completion'**
  String get taskDetailPieceProgress;

  /// No description provided for @taskDetailOverallProgress.
  ///
  /// In en, this message translates to:
  /// **'Overall progress'**
  String get taskDetailOverallProgress;

  /// No description provided for @speedGlobal.
  ///
  /// In en, this message translates to:
  /// **'↓ {down}  ↑ {up}  active {active}  waiting {waiting}'**
  String speedGlobal(String down, String up, int active, int waiting);

  /// No description provided for @speedGlobalExtended.
  ///
  /// In en, this message translates to:
  /// **'↓ {down}  ↑ {up}  active {active}  waiting {waiting}  stopped {stopped}'**
  String speedGlobalExtended(
    String down,
    String up,
    int active,
    int waiting,
    int stopped,
  );

  /// No description provided for @aria2Version.
  ///
  /// In en, this message translates to:
  /// **'aria2 {version}'**
  String aria2Version(String version);

  /// No description provided for @wsConnected.
  ///
  /// In en, this message translates to:
  /// **'WebSocket notifications connected'**
  String get wsConnected;

  /// No description provided for @wsPolling.
  ///
  /// In en, this message translates to:
  /// **'WebSocket unavailable; using periodic refresh'**
  String get wsPolling;

  /// No description provided for @emptyActive.
  ///
  /// In en, this message translates to:
  /// **'No active downloads'**
  String get emptyActive;

  /// No description provided for @emptyWaiting.
  ///
  /// In en, this message translates to:
  /// **'No waiting tasks'**
  String get emptyWaiting;

  /// No description provided for @emptyStopped.
  ///
  /// In en, this message translates to:
  /// **'No stopped tasks'**
  String get emptyStopped;

  /// No description provided for @hintUrls.
  ///
  /// In en, this message translates to:
  /// **'HTTP(S) / FTP / magnet links; separate with space or newline'**
  String get hintUrls;

  /// No description provided for @addButton.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addButton;

  /// No description provided for @snackAdded.
  ///
  /// In en, this message translates to:
  /// **'Download added'**
  String get snackAdded;

  /// No description provided for @snackAddFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String snackAddFailed(String error);

  /// No description provided for @snackInvalidUrl.
  ///
  /// In en, this message translates to:
  /// **'No valid URLs in input'**
  String get snackInvalidUrl;

  /// No description provided for @snackSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get snackSaved;

  /// No description provided for @advancedOptions.
  ///
  /// In en, this message translates to:
  /// **'Advanced…'**
  String get advancedOptions;

  /// No description provided for @userAgent.
  ///
  /// In en, this message translates to:
  /// **'User-Agent'**
  String get userAgent;

  /// No description provided for @headersHint.
  ///
  /// In en, this message translates to:
  /// **'HTTP headers, one per line: Name: Value'**
  String get headersHint;

  /// No description provided for @cookie.
  ///
  /// In en, this message translates to:
  /// **'Cookie header value (optional)'**
  String get cookie;

  /// No description provided for @speedLimitHint.
  ///
  /// In en, this message translates to:
  /// **'Speed limit (aria2 max-download-limit), e.g. 2M or 500K'**
  String get speedLimitHint;

  /// No description provided for @pickTorrent.
  ///
  /// In en, this message translates to:
  /// **'Pick .torrent'**
  String get pickTorrent;

  /// No description provided for @pickMetalink.
  ///
  /// In en, this message translates to:
  /// **'Pick Metalink (.metalink / .meta4)'**
  String get pickMetalink;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get openFolder;

  /// No description provided for @openFolderWebCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied the save path to the clipboard (browsers cannot open a local folder; path is from the aria2 server).'**
  String get openFolderWebCopied;

  /// No description provided for @openFolderFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open folder'**
  String get openFolderFailed;

  /// No description provided for @openFolderMobileDirOnly.
  ///
  /// In en, this message translates to:
  /// **'On mobile, opening only a folder in the file manager isn’t supported. Wait until a file exists, then open that file from the list.'**
  String get openFolderMobileDirOnly;

  /// No description provided for @openFileFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the file (invalid path, no app, or permission denied).'**
  String get openFileFailed;

  /// No description provided for @snackRetryQueued.
  ///
  /// In en, this message translates to:
  /// **'Download re-queued'**
  String get snackRetryQueued;

  /// No description provided for @snackNothingToRetry.
  ///
  /// In en, this message translates to:
  /// **'No links to retry for this task'**
  String get snackNothingToRetry;

  /// No description provided for @torrentNote.
  ///
  /// In en, this message translates to:
  /// **'Torrent/Metalink is sent to the local aria2 over RPC only.'**
  String get torrentNote;

  /// No description provided for @dialogCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get dialogCancel;

  /// No description provided for @torrentSelectDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose files to download'**
  String get torrentSelectDialogTitle;

  /// No description provided for @torrentSelectDialogConfirm.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get torrentSelectDialogConfirm;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutDesc.
  ///
  /// In en, this message translates to:
  /// **'Cross-platform download client powered by aria2.'**
  String get aboutDesc;

  /// No description provided for @appVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String appVersionLabel(String version);

  /// No description provided for @folderPickerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Folder picker is not available on this platform.'**
  String get folderPickerUnavailable;

  /// No description provided for @taskDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Task details'**
  String get taskDetailTitle;

  /// No description provided for @taskDetailLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Load failed: {error}'**
  String taskDetailLoadFailed(String error);

  /// No description provided for @taskDetailTabOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get taskDetailTabOverview;

  /// No description provided for @taskDetailTabFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get taskDetailTabFiles;

  /// No description provided for @taskDetailTabTorrent.
  ///
  /// In en, this message translates to:
  /// **'Torrent'**
  String get taskDetailTabTorrent;

  /// No description provided for @taskDetailFieldGid.
  ///
  /// In en, this message translates to:
  /// **'GID'**
  String get taskDetailFieldGid;

  /// No description provided for @taskDetailFieldStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get taskDetailFieldStatus;

  /// No description provided for @taskDetailFieldDir.
  ///
  /// In en, this message translates to:
  /// **'Directory'**
  String get taskDetailFieldDir;

  /// No description provided for @taskDetailFieldTotal.
  ///
  /// In en, this message translates to:
  /// **'Total size'**
  String get taskDetailFieldTotal;

  /// No description provided for @taskDetailFieldCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get taskDetailFieldCompleted;

  /// No description provided for @taskDetailFieldUploadLength.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get taskDetailFieldUploadLength;

  /// No description provided for @taskDetailFieldDownloadSpeed.
  ///
  /// In en, this message translates to:
  /// **'Download speed'**
  String get taskDetailFieldDownloadSpeed;

  /// No description provided for @taskDetailFieldUploadSpeed.
  ///
  /// In en, this message translates to:
  /// **'Upload speed'**
  String get taskDetailFieldUploadSpeed;

  /// No description provided for @taskDetailFieldConnections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get taskDetailFieldConnections;

  /// No description provided for @taskDetailFieldPieces.
  ///
  /// In en, this message translates to:
  /// **'Pieces'**
  String get taskDetailFieldPieces;

  /// No description provided for @taskDetailFieldBitfield.
  ///
  /// In en, this message translates to:
  /// **'Piece bitfield (hex)'**
  String get taskDetailFieldBitfield;

  /// No description provided for @taskDetailPieceSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} × {pieceSize}'**
  String taskDetailPieceSummary(String count, String pieceSize);

  /// No description provided for @taskDetailFieldError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get taskDetailFieldError;

  /// No description provided for @taskDetailNoFiles.
  ///
  /// In en, this message translates to:
  /// **'No file entries'**
  String get taskDetailNoFiles;

  /// No description provided for @taskDetailFileProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} / {total}'**
  String taskDetailFileProgress(String done, String total);

  /// No description provided for @taskDetailFileProgressSelected.
  ///
  /// In en, this message translates to:
  /// **'{done} / {total} · selected={selected}'**
  String taskDetailFileProgressSelected(
    String done,
    String total,
    String selected,
  );

  /// No description provided for @taskDetailNotTorrent.
  ///
  /// In en, this message translates to:
  /// **'This download is not a BitTorrent task.'**
  String get taskDetailNotTorrent;

  /// No description provided for @taskDetailTorrentName.
  ///
  /// In en, this message translates to:
  /// **'Torrent name'**
  String get taskDetailTorrentName;

  /// No description provided for @taskDetailTorrentMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get taskDetailTorrentMode;

  /// No description provided for @taskDetailAnnounceList.
  ///
  /// In en, this message translates to:
  /// **'Trackers / announce'**
  String get taskDetailAnnounceList;

  /// No description provided for @taskDetailAnnounceTier.
  ///
  /// In en, this message translates to:
  /// **'Tier {tier}'**
  String taskDetailAnnounceTier(int tier);

  /// No description provided for @taskDetailBtMetricsTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfer & connectivity'**
  String get taskDetailBtMetricsTitle;

  /// No description provided for @taskDetailFieldInfoHash.
  ///
  /// In en, this message translates to:
  /// **'Info hash'**
  String get taskDetailFieldInfoHash;

  /// No description provided for @taskDetailFieldNumSeeders.
  ///
  /// In en, this message translates to:
  /// **'Seeders (tracker-reported)'**
  String get taskDetailFieldNumSeeders;

  /// No description provided for @taskDetailFieldLocalSeeder.
  ///
  /// In en, this message translates to:
  /// **'This client is seeding'**
  String get taskDetailFieldLocalSeeder;

  /// No description provided for @taskDetailFieldBtConnections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get taskDetailFieldBtConnections;

  /// No description provided for @taskDetailTrackerRpcNote.
  ///
  /// In en, this message translates to:
  /// **'aria2 JSON-RPC does not expose per-tracker health; values below are task-level.'**
  String get taskDetailTrackerRpcNote;

  /// No description provided for @taskDetailBtRpcOptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'BitTorrent options (getOption)'**
  String get taskDetailBtRpcOptionsTitle;

  /// No description provided for @taskDetailBtRpcOptionsNote.
  ///
  /// In en, this message translates to:
  /// **'Effective values for this download in aria2.'**
  String get taskDetailBtRpcOptionsNote;

  /// No description provided for @taskDetailOptionEnableDht.
  ///
  /// In en, this message translates to:
  /// **'DHT (IPv4)'**
  String get taskDetailOptionEnableDht;

  /// No description provided for @taskDetailOptionEnableDht6.
  ///
  /// In en, this message translates to:
  /// **'DHT (IPv6)'**
  String get taskDetailOptionEnableDht6;

  /// No description provided for @taskDetailOptionBtEnableLpd.
  ///
  /// In en, this message translates to:
  /// **'Local peer discovery (LPD)'**
  String get taskDetailOptionBtEnableLpd;

  /// No description provided for @taskDetailBoolYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get taskDetailBoolYes;

  /// No description provided for @taskDetailBoolNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get taskDetailBoolNo;

  /// No description provided for @taskDetailNoAnnounces.
  ///
  /// In en, this message translates to:
  /// **'No announce list'**
  String get taskDetailNoAnnounces;

  /// No description provided for @taskDetailPeersTitle.
  ///
  /// In en, this message translates to:
  /// **'Peers ({count})'**
  String taskDetailPeersTitle(int count);

  /// No description provided for @taskDetailPeersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No peer data (not connected yet or task finished).'**
  String get taskDetailPeersEmpty;

  /// No description provided for @taskDetailPeerDown.
  ///
  /// In en, this message translates to:
  /// **'Down'**
  String get taskDetailPeerDown;

  /// No description provided for @taskDetailPeerUp.
  ///
  /// In en, this message translates to:
  /// **'Up'**
  String get taskDetailPeerUp;

  /// No description provided for @taskDetailSelectFilesHint.
  ///
  /// In en, this message translates to:
  /// **'Choose files to download, then apply to aria2 (waiting / paused / active tasks).'**
  String get taskDetailSelectFilesHint;

  /// No description provided for @taskDetailApplyFileSelection.
  ///
  /// In en, this message translates to:
  /// **'Apply file selection'**
  String get taskDetailApplyFileSelection;

  /// No description provided for @taskDetailFileSelectionApplyFailed.
  ///
  /// In en, this message translates to:
  /// **'Apply failed: {error}'**
  String taskDetailFileSelectionApplyFailed(String error);

  /// No description provided for @taskDetailNeedOneFileSelected.
  ///
  /// In en, this message translates to:
  /// **'Keep at least one file selected.'**
  String get taskDetailNeedOneFileSelected;

  /// No description provided for @taskDetailFileSelectionSaved.
  ///
  /// In en, this message translates to:
  /// **'File selection applied.'**
  String get taskDetailFileSelectionSaved;

  /// No description provided for @settingsConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get settingsConnection;

  /// No description provided for @connectionLocal.
  ///
  /// In en, this message translates to:
  /// **'Local aria2'**
  String get connectionLocal;

  /// No description provided for @connectionRemote.
  ///
  /// In en, this message translates to:
  /// **'Remote RPC'**
  String get connectionRemote;

  /// No description provided for @settingsEngine.
  ///
  /// In en, this message translates to:
  /// **'Local engine'**
  String get settingsEngine;

  /// No description provided for @engineLibrary.
  ///
  /// In en, this message translates to:
  /// **'Embedded library (libaria2)'**
  String get engineLibrary;

  /// No description provided for @engineSubprocess.
  ///
  /// In en, this message translates to:
  /// **'aria2c subprocess'**
  String get engineSubprocess;

  /// No description provided for @engineLibraryDesc.
  ///
  /// In en, this message translates to:
  /// **'Runs aria2 in-process via FFI. Lower memory, works on iOS, no extra binary required.'**
  String get engineLibraryDesc;

  /// No description provided for @engineSubprocessDesc.
  ///
  /// In en, this message translates to:
  /// **'Launches the bundled aria2c executable. Useful as a fallback when libaria2 fails to initialize.'**
  String get engineSubprocessDesc;

  /// No description provided for @engineFallbackToSubprocess.
  ///
  /// In en, this message translates to:
  /// **'Auto-fallback to subprocess'**
  String get engineFallbackToSubprocess;

  /// No description provided for @engineFallbackToSubprocessDesc.
  ///
  /// In en, this message translates to:
  /// **'When the embedded engine cannot start, retry with the aria2c subprocess.'**
  String get engineFallbackToSubprocessDesc;

  /// No description provided for @engineUnavailableBanner.
  ///
  /// In en, this message translates to:
  /// **'Embedded engine unavailable in this build — falling back to subprocess.'**
  String get engineUnavailableBanner;

  /// No description provided for @engineInitFailed.
  ///
  /// In en, this message translates to:
  /// **'Embedded engine failed to start: {error}'**
  String engineInitFailed(String error);

  /// No description provided for @engineCurrent.
  ///
  /// In en, this message translates to:
  /// **'Active engine: {engine}'**
  String engineCurrent(String engine);

  /// No description provided for @engineLibraryShort.
  ///
  /// In en, this message translates to:
  /// **'library'**
  String get engineLibraryShort;

  /// No description provided for @engineSubprocessShort.
  ///
  /// In en, this message translates to:
  /// **'subprocess'**
  String get engineSubprocessShort;

  /// No description provided for @engineRemoteShort.
  ///
  /// In en, this message translates to:
  /// **'remote'**
  String get engineRemoteShort;

  /// No description provided for @remoteRpcEndpoint.
  ///
  /// In en, this message translates to:
  /// **'RPC endpoint'**
  String get remoteRpcEndpoint;

  /// No description provided for @remoteRpcEndpointHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 127.0.0.1:6800 or http://nas:6800/jsonrpc'**
  String get remoteRpcEndpointHint;

  /// No description provided for @remoteRpcSecret.
  ///
  /// In en, this message translates to:
  /// **'RPC secret (token)'**
  String get remoteRpcSecret;

  /// No description provided for @remoteModeHint.
  ///
  /// In en, this message translates to:
  /// **'Remote mode does not start a local process. Ensure aria2 RPC is enabled and the secret matches.'**
  String get remoteModeHint;

  /// No description provided for @settingsDownloadTuning.
  ///
  /// In en, this message translates to:
  /// **'Download tuning (local aria2.conf)'**
  String get settingsDownloadTuning;

  /// No description provided for @settingsOptionalHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for aria2 default'**
  String get settingsOptionalHint;

  /// No description provided for @maxConcurrentDownloads.
  ///
  /// In en, this message translates to:
  /// **'Max concurrent downloads'**
  String get maxConcurrentDownloads;

  /// No description provided for @maxConnectionPerServer.
  ///
  /// In en, this message translates to:
  /// **'Max connections per server'**
  String get maxConnectionPerServer;

  /// No description provided for @globalDownloadLimit.
  ///
  /// In en, this message translates to:
  /// **'Global download limit'**
  String get globalDownloadLimit;

  /// No description provided for @globalUploadLimit.
  ///
  /// In en, this message translates to:
  /// **'Global upload limit'**
  String get globalUploadLimit;

  /// No description provided for @settingsTuningLocalOnly.
  ///
  /// In en, this message translates to:
  /// **'These options apply only in local aria2 mode (written to aria2.conf).'**
  String get settingsTuningLocalOnly;

  /// No description provided for @settingsDesktop.
  ///
  /// In en, this message translates to:
  /// **'Desktop'**
  String get settingsDesktop;

  /// No description provided for @closeToTray.
  ///
  /// In en, this message translates to:
  /// **'Close to system tray'**
  String get closeToTray;

  /// No description provided for @closeToTrayDesc.
  ///
  /// In en, this message translates to:
  /// **'The close button hides the window; use Quit in the tray menu to exit.'**
  String get closeToTrayDesc;

  /// No description provided for @minimizeToTray.
  ///
  /// In en, this message translates to:
  /// **'Minimize to tray'**
  String get minimizeToTray;

  /// No description provided for @minimizeToTrayDesc.
  ///
  /// In en, this message translates to:
  /// **'Hide the window when minimized (otherwise normal minimize).'**
  String get minimizeToTrayDesc;

  /// No description provided for @launchAtStartup.
  ///
  /// In en, this message translates to:
  /// **'Launch at login'**
  String get launchAtStartup;

  /// No description provided for @launchAtStartupDesc.
  ///
  /// In en, this message translates to:
  /// **'Start aria2down when you sign in (OS permissions may apply).'**
  String get launchAtStartupDesc;

  /// No description provided for @settingsBackup.
  ///
  /// In en, this message translates to:
  /// **'Backup & restore'**
  String get settingsBackup;

  /// No description provided for @settingsExport.
  ///
  /// In en, this message translates to:
  /// **'Export settings'**
  String get settingsExport;

  /// No description provided for @settingsImport.
  ///
  /// In en, this message translates to:
  /// **'Import settings'**
  String get settingsImport;

  /// No description provided for @settingsExportCopied.
  ///
  /// In en, this message translates to:
  /// **'Settings JSON copied to clipboard'**
  String get settingsExportCopied;

  /// No description provided for @settingsExportSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved to {path}'**
  String settingsExportSaved(String path);

  /// No description provided for @settingsImportApplied.
  ///
  /// In en, this message translates to:
  /// **'Settings loaded. Tap Save to persist, or edit first.'**
  String get settingsImportApplied;

  /// No description provided for @settingsImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String settingsImportFailed(String error);

  /// No description provided for @trayShowWindow.
  ///
  /// In en, this message translates to:
  /// **'Show window'**
  String get trayShowWindow;

  /// No description provided for @trayQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get trayQuit;

  /// No description provided for @trayToolTip.
  ///
  /// In en, this message translates to:
  /// **'aria2down — click to show'**
  String get trayToolTip;

  /// No description provided for @tasksBatchMenu.
  ///
  /// In en, this message translates to:
  /// **'Batch actions'**
  String get tasksBatchMenu;

  /// No description provided for @batchPauseAll.
  ///
  /// In en, this message translates to:
  /// **'Pause all'**
  String get batchPauseAll;

  /// No description provided for @batchForcePauseAll.
  ///
  /// In en, this message translates to:
  /// **'Force pause all'**
  String get batchForcePauseAll;

  /// No description provided for @batchExportTasks.
  ///
  /// In en, this message translates to:
  /// **'Export task snapshot'**
  String get batchExportTasks;

  /// No description provided for @batchExportTasksDone.
  ///
  /// In en, this message translates to:
  /// **'Task snapshot copied to clipboard'**
  String get batchExportTasksDone;

  /// No description provided for @batchUnpauseAll.
  ///
  /// In en, this message translates to:
  /// **'Resume all'**
  String get batchUnpauseAll;

  /// No description provided for @settingsDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get settingsDiagnostics;

  /// No description provided for @aria2LogTitle.
  ///
  /// In en, this message translates to:
  /// **'aria2 log'**
  String get aria2LogTitle;

  /// No description provided for @aria2LogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Last lines from the local aria2 log file'**
  String get aria2LogSubtitle;

  /// No description provided for @aria2LogEmpty.
  ///
  /// In en, this message translates to:
  /// **'Log file is empty or not created yet.'**
  String get aria2LogEmpty;

  /// No description provided for @batchPurgeStopped.
  ///
  /// In en, this message translates to:
  /// **'Purge stopped results'**
  String get batchPurgeStopped;

  /// No description provided for @snackBatchDone.
  ///
  /// In en, this message translates to:
  /// **'Batch action completed'**
  String get snackBatchDone;

  /// No description provided for @pasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from clipboard'**
  String get pasteFromClipboard;

  /// No description provided for @clipboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'Clipboard is empty'**
  String get clipboardEmpty;

  /// No description provided for @applyRuntimeLimits.
  ///
  /// In en, this message translates to:
  /// **'Apply to running aria2'**
  String get applyRuntimeLimits;

  /// No description provided for @applyRuntimeLimitsHint.
  ///
  /// In en, this message translates to:
  /// **'Updates global limits without restart (local or remote).'**
  String get applyRuntimeLimitsHint;

  /// No description provided for @applyRuntimeLimitsDone.
  ///
  /// In en, this message translates to:
  /// **'Running options updated'**
  String get applyRuntimeLimitsDone;

  /// No description provided for @applyRuntimeLimitsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one limit or concurrency value'**
  String get applyRuntimeLimitsEmpty;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About aria2down'**
  String get aboutTitle;

  /// No description provided for @aboutOpenDetail.
  ///
  /// In en, this message translates to:
  /// **'Version, license, and links'**
  String get aboutOpenDetail;

  /// No description provided for @aboutPoweredBy.
  ///
  /// In en, this message translates to:
  /// **'Download engine'**
  String get aboutPoweredBy;

  /// No description provided for @aboutLicense.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get aboutLicense;

  /// No description provided for @aboutLicenseBody.
  ///
  /// In en, this message translates to:
  /// **'Released under GPLv2+, compatible with aria2.'**
  String get aboutLicenseBody;

  /// No description provided for @aboutLicenseLink.
  ///
  /// In en, this message translates to:
  /// **'GNU GPLv2 full text'**
  String get aboutLicenseLink;

  /// No description provided for @platformHintMessage.
  ///
  /// In en, this message translates to:
  /// **'Downloads may pause when the app is in the background. Keep the app open or use Remote RPC to a server that stays online.'**
  String get platformHintMessage;

  /// No description provided for @platformHintOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get platformHintOpenSettings;

  /// No description provided for @platformHintDismiss.
  ///
  /// In en, this message translates to:
  /// **'Don\'t show again'**
  String get platformHintDismiss;

  /// No description provided for @mobileSettingsCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Mobile tips'**
  String get mobileSettingsCardTitle;

  /// No description provided for @mobileSettingsCardBody.
  ///
  /// In en, this message translates to:
  /// **'Local mode downloads inside the app. Switch to Remote RPC to use aria2 on a NAS or PC. Background downloads may pause when the screen is locked.'**
  String get mobileSettingsCardBody;

  /// No description provided for @welcomeUseLocal.
  ///
  /// In en, this message translates to:
  /// **'Use local download'**
  String get welcomeUseLocal;

  /// No description provided for @welcomeSetupRemote.
  ///
  /// In en, this message translates to:
  /// **'Set up remote RPC'**
  String get welcomeSetupRemote;

  /// No description provided for @daemonErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Cannot connect to aria2'**
  String get daemonErrorTitle;

  /// No description provided for @daemonErrorBinaryNotFound.
  ///
  /// In en, this message translates to:
  /// **'aria2c not found. Install aria2, set a path in Settings, bundle a binary in assets, or use Remote RPC.'**
  String get daemonErrorBinaryNotFound;

  /// No description provided for @daemonErrorWebLocal.
  ///
  /// In en, this message translates to:
  /// **'The browser cannot start a local aria2 process. Use Remote RPC in Settings.'**
  String get daemonErrorWebLocal;

  /// No description provided for @daemonErrorRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get daemonErrorRetry;

  /// No description provided for @daemonErrorSwitchRemote.
  ///
  /// In en, this message translates to:
  /// **'Switch to remote RPC'**
  String get daemonErrorSwitchRemote;

  /// No description provided for @welcomeRemoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to aria2down'**
  String get welcomeRemoteTitle;

  /// No description provided for @welcomeRemoteBody.
  ///
  /// In en, this message translates to:
  /// **'Download on this device with the built-in engine, or connect to aria2 on a NAS or PC via Remote RPC in Settings.'**
  String get welcomeRemoteBody;

  /// No description provided for @snackAllDuplicates.
  ///
  /// In en, this message translates to:
  /// **'These links are already in the queue'**
  String get snackAllDuplicates;

  /// No description provided for @snackAddedWithSkipped.
  ///
  /// In en, this message translates to:
  /// **'Added {added}; skipped {skipped} duplicate(s)'**
  String snackAddedWithSkipped(int added, int skipped);

  /// No description provided for @batchRemoveStopped.
  ///
  /// In en, this message translates to:
  /// **'Remove all stopped tasks'**
  String get batchRemoveStopped;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @swipeDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove task?'**
  String get swipeDeleteTitle;

  /// No description provided for @swipeDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This removes the task from aria2 (files on disk are kept unless you enabled delete-on-remove).'**
  String get swipeDeleteMessage;

  /// No description provided for @remoteTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get remoteTestConnection;

  /// No description provided for @remoteTestOk.
  ///
  /// In en, this message translates to:
  /// **'Connected — aria2 {version}, WebSocket: {ws}'**
  String remoteTestOk(String version, String ws);

  /// No description provided for @remoteTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}'**
  String remoteTestFailed(String error);

  /// No description provided for @aboutRpcInfo.
  ///
  /// In en, this message translates to:
  /// **'Current RPC'**
  String get aboutRpcInfo;

  /// No description provided for @aboutRpcSecretHint.
  ///
  /// In en, this message translates to:
  /// **'RPC token (for extensions / remote clients on this machine):'**
  String get aboutRpcSecretHint;

  /// No description provided for @taskShare.
  ///
  /// In en, this message translates to:
  /// **'Copy share text'**
  String get taskShare;

  /// No description provided for @aria2GlobalOptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'aria2 global options'**
  String get aria2GlobalOptionsTitle;

  /// No description provided for @aria2GlobalOptionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read-only list from running aria2'**
  String get aria2GlobalOptionsSubtitle;

  /// No description provided for @copyRpcConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Copy RPC config for extension'**
  String get copyRpcConfigTitle;

  /// No description provided for @copyRpcConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'JSON for Chrome extension options (after local aria2 has started once)'**
  String get copyRpcConfigSubtitle;

  /// No description provided for @copyRpcConfigDone.
  ///
  /// In en, this message translates to:
  /// **'RPC config copied to clipboard'**
  String get copyRpcConfigDone;

  /// No description provided for @copyRpcConfigUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Start local aria2 once to generate rpc.secret'**
  String get copyRpcConfigUnavailable;

  /// No description provided for @taskActionPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get taskActionPause;

  /// No description provided for @taskActionResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get taskActionResume;

  /// No description provided for @taskActionForcePause.
  ///
  /// In en, this message translates to:
  /// **'Force pause'**
  String get taskActionForcePause;

  /// No description provided for @settingsWebRemoteOnly.
  ///
  /// In en, this message translates to:
  /// **'Web builds only support Remote RPC.'**
  String get settingsWebRemoteOnly;

  /// No description provided for @connectionStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Current connection'**
  String get connectionStatusTitle;

  /// No description provided for @connectionStatusLoading.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connectionStatusLoading;

  /// No description provided for @connectionStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get connectionStatusOffline;

  /// No description provided for @connectionStatusWs.
  ///
  /// In en, this message translates to:
  /// **'WebSocket notifications: {status}'**
  String connectionStatusWs(String status);

  /// No description provided for @desktopShortcutRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh task list'**
  String get desktopShortcutRefresh;

  /// No description provided for @desktopShortcutSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get desktopShortcutSettings;

  /// No description provided for @pasteAndAdd.
  ///
  /// In en, this message translates to:
  /// **'Paste and add'**
  String get pasteAndAdd;

  /// No description provided for @snackAddedCount.
  ///
  /// In en, this message translates to:
  /// **'Added {count} task(s)'**
  String snackAddedCount(int count);

  /// No description provided for @copyTaskUris.
  ///
  /// In en, this message translates to:
  /// **'Copy all URIs'**
  String get copyTaskUris;

  /// No description provided for @settingsDangerZone.
  ///
  /// In en, this message translates to:
  /// **'Advanced / danger zone'**
  String get settingsDangerZone;

  /// No description provided for @shutdownAria2.
  ///
  /// In en, this message translates to:
  /// **'Shut down aria2'**
  String get shutdownAria2;

  /// No description provided for @shutdownAria2Title.
  ///
  /// In en, this message translates to:
  /// **'Shut down aria2?'**
  String get shutdownAria2Title;

  /// No description provided for @shutdownAria2Message.
  ///
  /// In en, this message translates to:
  /// **'Gracefully stops the aria2 daemon. Active downloads will stop. You can reconnect later.'**
  String get shutdownAria2Message;

  /// No description provided for @shutdownAria2Confirm.
  ///
  /// In en, this message translates to:
  /// **'Shut down'**
  String get shutdownAria2Confirm;

  /// No description provided for @shutdownAria2Done.
  ///
  /// In en, this message translates to:
  /// **'aria2 shut down'**
  String get shutdownAria2Done;

  /// No description provided for @resetSettings.
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get resetSettings;

  /// No description provided for @resetSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset settings?'**
  String get resetSettingsTitle;

  /// No description provided for @resetSettingsMessage.
  ///
  /// In en, this message translates to:
  /// **'Clears all app settings (task history file is kept). aria2 will reconnect.'**
  String get resetSettingsMessage;

  /// No description provided for @resetSettingsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetSettingsConfirm;

  /// No description provided for @resetSettingsDone.
  ///
  /// In en, this message translates to:
  /// **'Settings reset'**
  String get resetSettingsDone;

  /// No description provided for @copyAddTaskLink.
  ///
  /// In en, this message translates to:
  /// **'Copy in-app add link'**
  String get copyAddTaskLink;

  /// No description provided for @taskContextViewDetail.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get taskContextViewDetail;

  /// No description provided for @desktopShortcutAdd.
  ///
  /// In en, this message translates to:
  /// **'New download task'**
  String get desktopShortcutAdd;

  /// No description provided for @aboutDesktopShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts (desktop)'**
  String get aboutDesktopShortcuts;

  /// No description provided for @globalOptionsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search options…'**
  String get globalOptionsSearchHint;

  /// No description provided for @copyDeepLinkExampleTitle.
  ///
  /// In en, this message translates to:
  /// **'Copy example add-task link'**
  String get copyDeepLinkExampleTitle;

  /// No description provided for @copyDeepLinkExampleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'In-app path like /add?uri=… — see docs/DEEPLINKS.md'**
  String get copyDeepLinkExampleSubtitle;

  /// No description provided for @copyDeepLinkExampleDone.
  ///
  /// In en, this message translates to:
  /// **'Example deep link copied'**
  String get copyDeepLinkExampleDone;

  /// No description provided for @rpcErrorConnection.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach aria2 RPC. Check that aria2 is running and Settings → RPC address is correct.'**
  String get rpcErrorConnection;

  /// No description provided for @rpcErrorUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'RPC rejected the request. Check the token / secret in Settings.'**
  String get rpcErrorUnauthorized;

  /// No description provided for @rpcErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Request failed: {error}'**
  String rpcErrorGeneric(String error);

  /// No description provided for @copyRpcEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Copy RPC URL'**
  String get copyRpcEndpoint;

  /// No description provided for @batchExportHistory.
  ///
  /// In en, this message translates to:
  /// **'Export history (JSON)'**
  String get batchExportHistory;

  /// No description provided for @batchExportHistoryDone.
  ///
  /// In en, this message translates to:
  /// **'Task history copied to clipboard'**
  String get batchExportHistoryDone;

  /// No description provided for @batchClearStoppedResults.
  ///
  /// In en, this message translates to:
  /// **'Clear stopped list (keep files)'**
  String get batchClearStoppedResults;

  /// No description provided for @pasteAndQueue.
  ///
  /// In en, this message translates to:
  /// **'Paste and queue'**
  String get pasteAndQueue;

  /// No description provided for @batchImportHistory.
  ///
  /// In en, this message translates to:
  /// **'Import history from clipboard'**
  String get batchImportHistory;

  /// No description provided for @historyImportDone.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} history record(s)'**
  String historyImportDone(int count);

  /// No description provided for @historyImportFailed.
  ///
  /// In en, this message translates to:
  /// **'History import failed: {error}'**
  String historyImportFailed(String error);

  /// No description provided for @copyGlobalOptions.
  ///
  /// In en, this message translates to:
  /// **'Copy all options'**
  String get copyGlobalOptions;

  /// No description provided for @copyGlobalOptionsDone.
  ///
  /// In en, this message translates to:
  /// **'Global options copied to clipboard'**
  String get copyGlobalOptionsDone;

  /// No description provided for @aboutBrowserExtension.
  ///
  /// In en, this message translates to:
  /// **'Browser extension'**
  String get aboutBrowserExtension;

  /// No description provided for @aboutBrowserExtensionHint.
  ///
  /// In en, this message translates to:
  /// **'See extensions/README.md in the repository'**
  String get aboutBrowserExtensionHint;

  /// No description provided for @aria2LogSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search log lines…'**
  String get aria2LogSearchHint;

  /// No description provided for @aria2LogNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No log lines match your search.'**
  String get aria2LogNoMatch;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
