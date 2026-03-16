import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/backend_config.dart';
import '../../../core/localization/app_i18n.dart';
import '../../../core/localization/app_language.dart';
import '../../../core/storage/widget_snapshot_store.dart';
import '../../../integrations/backend_api/api_client.dart';
import '../../../integrations/widget_host/widget_host_bridge.dart';
import '../../settings/presentation/color_schema_editor.dart';
import '../../settings/presentation/settings_panel.dart';
import '../application/widget_snapshot_builder.dart';
import '../data/calendar_events_repository.dart';
import '../domain/models/calendar_event.dart';
import '../domain/models/widget_snapshot.dart';
import 'analog_clock_card.dart';
import 'clock_screen_saver_page.dart';
import 'mobile_detail_pages.dart';

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key, this.startInScreenSaverMode = false});

  final bool startInScreenSaverMode;

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen>
    with WidgetsBindingObserver {
  static const String _labsEventDetailBottomSheetKey =
      'labs_event_detail_bottom_sheet';
  static const String _screenSaverBottomPanelVisibleKey =
      'screen_saver_bottom_panel_visible_v1';
  static const String _loginLinkingOnboardingCompletedKey =
      'login_linking_onboarding_completed_v1';
  static const String _lockScreenAutoModeEnabledKey =
      'lock_screen_auto_mode_enabled_v1';
  static const String _hostLaunchActionOpenScreenSaver = 'open_screen_saver';
  static const Duration _deepLinkDedupWindow = Duration(seconds: 5);
  static const Duration _resumeRefreshDebounce = Duration(seconds: 2);
  static const int _clockTabIndex = 0;
  static const int _settingsTabIndex = 1;

  late final WidgetSnapshotStore _snapshotStore;
  late final WidgetHostBridge _widgetHostBridge;
  late final CalendarEventsRepository _eventsRepository;
  late final String _backendBaseUrl;
  late Future<WidgetSnapshot> _snapshotFuture;
  WidgetSnapshot? _lastGoodSnapshot;
  String _loadSource = 'cache';
  String _activeProvider = 'google';
  String _selectedProvider = 'google';
  List<String> _providers = const <String>['google', 'apple'];
  bool? _providerAuthenticated;
  String? _providerAccountLabel;
  String? _providerAccountEmail;
  bool _authFlowBusy = false;
  bool _logoutFlowBusy = false;
  String? _googleRedirectUri;
  Timer? _authStatusPollTimer;
  int _authStatusPollAttempts = 0;
  Future<bool>? _authRefreshInFlight;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _deepLinkSubscription;
  String? _lastHandledDeepLinkSignature;
  DateTime? _lastHandledDeepLinkAt;
  DateTime? _lastLifecycleResumeRefreshAt;
  final TextEditingController _appleIdController = TextEditingController();
  final TextEditingController _applePasswordController =
      TextEditingController();
  bool _appleCredentialBusy = false;
  Timer? _eventsRefreshTicker;
  bool _snapshotReloadInFlight = false;
  String _widgetThemeForSnapshot = 'dark';
  bool _widgetThemeLoaded = false;
  bool _labsEventDetailBottomSheetEnabled = false;
  bool _screenSaverBottomPanelVisible = true;
  bool _screenSaverUiSettingsLoaded = false;
  bool _loginLinkingOnboardingCompleted = false;
  bool _loginLinkingOnboardingFlowPresented = false;
  bool _loginLinkingOnboardingRouteOpen = false;
  bool _lockScreenAutoModeEnabled = false;
  bool _lockScreenAutoModeToggleInFlight = false;
  bool _lockScreenAutoModeNotificationBlocked = false;
  bool _screenSaverRouteOpen = false;
  bool _launchActionHandlingInFlight = false;
  bool _startupScreenSaverPending = false;
  int _selectedBottomNavIndex = _clockTabIndex;
  DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startupScreenSaverPending = widget.startInScreenSaverMode;
    _snapshotStore = FileWidgetSnapshotStore();
    _widgetHostBridge = WidgetHostBridge();
    _backendBaseUrl = BackendConfig.resolveBaseUrl();
    final apiClient = BackendApiClient(baseUrl: _backendBaseUrl);
    _eventsRepository = CalendarEventsRepository(apiClient: apiClient);
    if (_startupScreenSaverPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_startInScreenSaverModeIfNeeded());
        }
      });
    }

    _snapshotFuture = _bootstrapLoad();
    _snapshotFuture.then((_) {
      if (!mounted) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (!_startupScreenSaverPending) {
            unawaited(_maybeHandleHostLaunchAction());
            unawaited(_maybePresentLoginLinkingOnboarding());
          }
        }
      });
    });
    _eventsRefreshTicker = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) {
        _regenerateSnapshot();
      }
    });
    _initDeepLinkHandling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAuthStatusPolling();
    _deepLinkSubscription?.cancel();
    _eventsRefreshTicker?.cancel();
    _appleIdController.dispose();
    _applePasswordController.dispose();
    _eventsRepository.dispose();
    super.dispose();
  }

  Future<void> _initDeepLinkHandling() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        await _handleIncomingDeepLink(initial);
      }
    } catch (_) {
      // Ignore deep-link bootstrap failures and keep app usable.
    }

    _deepLinkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleIncomingDeepLink(uri);
    });
  }

  Future<void> _handleIncomingDeepLink(Uri uri) async {
    if (!mounted) {
      return;
    }

    if (uri.scheme != 'smartanalog') {
      return;
    }
    if (uri.host != 'auth') {
      return;
    }

    final path = uri.path.toLowerCase();
    if (path != '/google' && path != 'google') {
      return;
    }

    final signature = _deepLinkSignature(uri);
    final now = DateTime.now();
    final lastSignature = _lastHandledDeepLinkSignature;
    final lastHandledAt = _lastHandledDeepLinkAt;
    if (lastSignature == signature &&
        lastHandledAt != null &&
        now.difference(lastHandledAt) < _deepLinkDedupWindow) {
      return;
    }
    _lastHandledDeepLinkSignature = signature;
    _lastHandledDeepLinkAt = now;

    _stopAuthStatusPolling();

    final status = (uri.queryParameters['status'] ?? '').toLowerCase();
    final message = uri.queryParameters['message'] ?? '';
    if (mounted && status.isNotEmpty) {
      final i18n = context.i18n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isNotEmpty
                ? message
                : (status == 'success'
                      ? i18n.googleAuthCompleted
                      : i18n.googleAuthFailed),
          ),
        ),
      );
    }

    await _refreshAuthStatusAndMaybeReload(includeIdentity: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }

    final now = DateTime.now();
    final lastRefreshAt = _lastLifecycleResumeRefreshAt;
    if (lastRefreshAt != null &&
        now.difference(lastRefreshAt) < _resumeRefreshDebounce) {
      return;
    }

    _lastLifecycleResumeRefreshAt = now;
    unawaited(_refreshAuthStatusAndMaybeReload());
    unawaited(_maybeHandleHostLaunchAction());
  }

  Future<WidgetSnapshot> _bootstrapLoad() async {
    await _loadLabsSettings();
    _lockScreenAutoModeNotificationBlocked = false;
    if (_lockScreenAutoModeEnabled) {
      final hasCorePermission = await _ensureAutoLockCorePermission(
        interactive: false,
      );
      if (!hasCorePermission) {
        _lockScreenAutoModeNotificationBlocked = true;
      }
    }
    await _syncLockScreenAutoModeWithHost();
    await _loadProvidersAndStatus();
    await _refreshWidgetThemeSetting(force: true);
    return _loadOrCreateSnapshot(
      provider: _selectedProvider,
      selectedDate: _selectedDate,
      allowCacheFallback: true,
    );
  }

  Future<void> _refreshWidgetThemeSetting({bool force = false}) async {
    if (!force && _widgetThemeLoaded) {
      return;
    }
    try {
      final settings = await _eventsRepository.fetchSettings();
      _widgetThemeForSnapshot = _normalizeWidgetTheme(settings.widgetTheme);
      _widgetThemeLoaded = true;
    } catch (_) {
      if (!_widgetThemeLoaded) {
        _widgetThemeForSnapshot = 'dark';
      }
    }
  }

  Future<void> _loadLabsSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _labsEventDetailBottomSheetEnabled =
          prefs.getBool(_labsEventDetailBottomSheetKey) ?? false;
      _screenSaverBottomPanelVisible =
          prefs.getBool(_screenSaverBottomPanelVisibleKey) ?? true;
      _loginLinkingOnboardingCompleted =
          prefs.getBool(_loginLinkingOnboardingCompletedKey) ?? false;
      _lockScreenAutoModeEnabled =
          prefs.getBool(_lockScreenAutoModeEnabledKey) ?? false;
      _screenSaverUiSettingsLoaded = true;
    } catch (_) {
      _labsEventDetailBottomSheetEnabled = false;
      _screenSaverBottomPanelVisible = true;
      _loginLinkingOnboardingCompleted = false;
      _lockScreenAutoModeEnabled = false;
      _screenSaverUiSettingsLoaded = false;
    }
  }

  Future<void> _ensureScreenSaverUiSettingsLoaded() async {
    if (_screenSaverUiSettingsLoaded) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _labsEventDetailBottomSheetEnabled =
          prefs.getBool(_labsEventDetailBottomSheetKey) ?? false;
      _screenSaverBottomPanelVisible =
          prefs.getBool(_screenSaverBottomPanelVisibleKey) ?? true;
      _screenSaverUiSettingsLoaded = true;
    } catch (_) {
      _labsEventDetailBottomSheetEnabled = false;
      _screenSaverBottomPanelVisible = true;
      _screenSaverUiSettingsLoaded = false;
    }
  }

  Future<bool> _syncLockScreenAutoModeWithHost() async {
    if (_lockScreenAutoModeEnabled && !_lockScreenAutoModeNotificationBlocked) {
      return _widgetHostBridge.enableAutoLockScreenMode();
    }
    return _widgetHostBridge.disableAutoLockScreenMode();
  }

  Future<void> _persistLockScreenAutoMode(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_lockScreenAutoModeEnabledKey, enabled);
    } catch (_) {
      // Keep app behavior resilient even if preference persistence fails.
    }
  }

  Future<bool> _ensureAutoLockCorePermission({
    required bool interactive,
  }) async {
    if (!Platform.isAndroid) {
      return true;
    }
    final hasNotificationPermission = await _widgetHostBridge
        .checkNotificationPermission();
    if (hasNotificationPermission) {
      return true;
    }
    if (!interactive) {
      return false;
    }

    final granted = await _widgetHostBridge.requestNotificationPermission();
    if (granted) {
      return true;
    }
    if (!mounted) {
      return false;
    }

    final i18n = context.i18n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(i18n.lockScreenNotificationPermissionRequired),
        action: SnackBarAction(
          label: i18n.openSettingsAction,
          onPressed: () {
            unawaited(
              _widgetHostBridge.openNotificationSettings().then((opened) {
                if (!opened && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        i18n.permissionStatusOpenSettingsFailed(
                          i18n.permissionStatusNotificationLabel,
                        ),
                      ),
                    ),
                  );
                }
              }),
            );
          },
        ),
      ),
    );
    return false;
  }

  Future<void> _maybePromptBatteryOptimizationRecommendation() async {
    if (!Platform.isAndroid) {
      return;
    }
    final ignored = await _widgetHostBridge.isIgnoringBatteryOptimizations();
    if (ignored || !mounted) {
      return;
    }

    final i18n = context.i18n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(i18n.lockScreenBatteryOptimizationHint),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: i18n.openSettingsAction,
          onPressed: () {
            unawaited(_widgetHostBridge.openBatteryOptimizationSettings());
          },
        ),
      ),
    );
  }

  Future<void> _maybePromptFullScreenIntentRecommendation() async {
    if (!Platform.isAndroid) {
      return;
    }
    final canUseFullScreenIntent = await _widgetHostBridge
        .canUseFullScreenIntent();
    if (canUseFullScreenIntent || !mounted) {
      return;
    }

    final i18n = context.i18n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(i18n.lockScreenFullScreenIntentHint),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: i18n.openSettingsAction,
          onPressed: () {
            unawaited(_widgetHostBridge.openFullScreenIntentSettings());
          },
        ),
      ),
    );
  }

  Future<void> _maybePromptOverlayPermissionRecommendation() async {
    if (!Platform.isAndroid) {
      return;
    }
    final canDrawOverlays = await _widgetHostBridge.canDrawOverlays();
    if (canDrawOverlays || !mounted) {
      return;
    }

    final i18n = context.i18n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(i18n.lockScreenOverlayPermissionHint),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: i18n.openSettingsAction,
          onPressed: () {
            unawaited(_widgetHostBridge.openOverlayPermissionSettings());
          },
        ),
      ),
    );
  }

  Future<void> _startInScreenSaverModeIfNeeded() async {
    if (!_startupScreenSaverPending || _screenSaverRouteOpen) {
      return;
    }
    await _ensureScreenSaverUiSettingsLoaded();
    await _openClockScreenSaverPage(
      preferFastEntry: true,
      instantTransition: true,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _startupScreenSaverPending = false;
    });
  }

  Future<void> _toggleLockScreenAutoMode() async {
    if (_lockScreenAutoModeToggleInFlight) {
      return;
    }
    _lockScreenAutoModeToggleInFlight = true;

    final nextValue = !_lockScreenAutoModeEnabled;
    if (nextValue) {
      final hasCorePermission = await _ensureAutoLockCorePermission(
        interactive: true,
      );
      if (!hasCorePermission) {
        if (mounted) {
          setState(() {
            _lockScreenAutoModeNotificationBlocked = true;
          });
        } else {
          _lockScreenAutoModeNotificationBlocked = true;
        }
        if (mounted) {
          setState(() {
            _lockScreenAutoModeToggleInFlight = false;
          });
        } else {
          _lockScreenAutoModeToggleInFlight = false;
        }
        return;
      }
    }

    final previousValue = _lockScreenAutoModeEnabled;
    final previousBlockedValue = _lockScreenAutoModeNotificationBlocked;
    setState(() {
      _lockScreenAutoModeEnabled = nextValue;
      _lockScreenAutoModeNotificationBlocked = false;
    });

    try {
      final synced = await _syncLockScreenAutoModeWithHost();
      if (!mounted) {
        return;
      }
      final i18n = context.i18n;
      if (!synced) {
        setState(() {
          _lockScreenAutoModeEnabled = previousValue;
          _lockScreenAutoModeNotificationBlocked = previousBlockedValue;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(i18n.lockScreenAutoModeSyncFailed)),
        );
        return;
      }

      await _persistLockScreenAutoMode(nextValue);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextValue
                ? i18n.lockScreenAutoModeEnabled
                : i18n.lockScreenAutoModeDisabled,
          ),
        ),
      );
      if (nextValue) {
        unawaited(_maybePromptBatteryOptimizationRecommendation());
        unawaited(_maybePromptFullScreenIntentRecommendation());
        unawaited(_maybePromptOverlayPermissionRecommendation());
        unawaited(_maybeHandleHostLaunchAction());
      }
    } finally {
      if (mounted) {
        setState(() {
          _lockScreenAutoModeToggleInFlight = false;
        });
      } else {
        _lockScreenAutoModeToggleInFlight = false;
      }
    }
  }

  Future<void> _maybeHandleHostLaunchAction() async {
    if (_launchActionHandlingInFlight) {
      return;
    }
    _launchActionHandlingInFlight = true;
    try {
      final action = await _widgetHostBridge.consumeLaunchAction();
      if (!mounted || action != _hostLaunchActionOpenScreenSaver) {
        return;
      }
      if (!_lockScreenAutoModeEnabled || _screenSaverRouteOpen) {
        return;
      }
      await _openClockScreenSaverPage(
        preferFastEntry: true,
        instantTransition: true,
      );
    } finally {
      _launchActionHandlingInFlight = false;
    }
  }

  Future<void> _maybePresentLoginLinkingOnboarding() async {
    if (!mounted ||
        _loginLinkingOnboardingCompleted ||
        _loginLinkingOnboardingFlowPresented) {
      return;
    }

    _loginLinkingOnboardingFlowPresented = true;
    await _refreshProviderStatus(
      provider: _selectedProvider,
      includeIdentity: true,
    );

    if (!mounted) {
      _loginLinkingOnboardingFlowPresented = false;
      return;
    }

    if (_providerAuthenticated == true) {
      await _markLoginLinkingOnboardingCompleted();
      _loginLinkingOnboardingFlowPresented = false;
      return;
    }

    _loginLinkingOnboardingRouteOpen = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LoginLinkingOnboardingPage(
            activeProvider: _activeProvider,
            selectedProvider: _selectedProvider,
            providers: _providers,
            providerAuthenticated: _providerAuthenticated,
            providerAccountLabel: _providerAccountLabel,
            providerAccountEmail: _providerAccountEmail,
            authFlowBusy: _authFlowBusy,
            logoutBusy: _logoutFlowBusy,
            googleRedirectUri: _googleRedirectUri,
            appleCredentialBusy: _appleCredentialBusy,
            appleIdController: _appleIdController,
            applePasswordController: _applePasswordController,
            onProviderChanged: _onProviderChanged,
            onStartGoogleAuth: _startGoogleAuthFlow,
            onSwitchGoogleAccount: _switchGoogleAccount,
            onSubmitAppleCredentials: _submitAppleCredentials,
            onLogoutProvider: () => unawaited(_logoutSelectedProvider()),
            onRefreshAuthOnly: _refreshAuthOnly,
          ),
        ),
      );
    } finally {
      _loginLinkingOnboardingRouteOpen = false;
      _loginLinkingOnboardingFlowPresented = false;
    }
  }

  Future<void> _markLoginLinkingOnboardingCompleted() async {
    if (_loginLinkingOnboardingCompleted) {
      return;
    }
    _loginLinkingOnboardingCompleted = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_loginLinkingOnboardingCompletedKey, true);
    } catch (_) {
      // Keep in-memory completion state even if persistence fails.
    }

    if (!mounted) {
      return;
    }
    setState(() {});

    if (_loginLinkingOnboardingRouteOpen && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _onLabsEventDetailBottomSheetChanged(bool enabled) {
    setState(() {
      _labsEventDetailBottomSheetEnabled = enabled;
    });
    unawaited(_persistLabsSettings(enabled));
  }

  void _onScreenSaverBottomPanelVisibleChanged(bool enabled) {
    setState(() {
      _screenSaverBottomPanelVisible = enabled;
    });
    unawaited(_persistScreenSaverUiSettings(enabled));
  }

  Future<void> _persistLabsSettings(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_labsEventDetailBottomSheetKey, enabled);
    } catch (_) {
      // Keep local UI state even if persistence fails.
    }
  }

  Future<void> _persistScreenSaverUiSettings(bool showBottomPanel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_screenSaverBottomPanelVisibleKey, showBottomPanel);
    } catch (_) {
      // Keep local UI state even if persistence fails.
    }
  }

  Future<void> _loadProvidersAndStatus() async {
    try {
      final providersResponse = await _eventsRepository.fetchProviders();
      final resolvedProviders = providersResponse.providers;
      if (resolvedProviders.isNotEmpty) {
        _providers = resolvedProviders;
      }

      if (_providers.contains(providersResponse.defaultProvider)) {
        _selectedProvider = providersResponse.defaultProvider;
      } else if (_providers.isNotEmpty) {
        _selectedProvider = _providers.first;
      }
    } catch (_) {
      // Keep defaults.
    }

    await _refreshProviderStatus(
      provider: _selectedProvider,
      includeIdentity: true,
    );
  }

  Future<void> _refreshProviderStatus({
    required String provider,
    bool includeIdentity = false,
  }) async {
    try {
      final status = await _eventsRepository.fetchProviderStatus(
        provider: provider,
        includeIdentity: includeIdentity,
      );
      _providerAuthenticated = status.authenticated;
      _activeProvider = status.provider;
      _providerAccountLabel = status.accountLabel;
      _providerAccountEmail = status.accountEmail;
    } catch (_) {
      _providerAuthenticated = null;
      _activeProvider = provider;
      _providerAccountLabel = null;
      _providerAccountEmail = null;
    }
  }

  Future<WidgetSnapshot> _loadOrCreateSnapshot({
    required String provider,
    required DateTime selectedDate,
    required bool allowCacheFallback,
  }) async {
    await _refreshWidgetThemeSetting();
    final selectedIsToday = _isSameCalendarDate(selectedDate, DateTime.now());
    try {
      final backendEvents = await _eventsRepository.fetchTodayEvents(
        provider: provider,
        maxResults: 200,
        date: selectedDate,
      );
      final now = DateTime.now();
      final freshSnapshot = const WidgetSnapshotBuilder().build(
        now: now,
        timezone: now.timeZoneName.isEmpty ? 'UTC' : now.timeZoneName,
        events: backendEvents,
        theme: _widgetThemeForSnapshot,
      );
      if (selectedIsToday) {
        await _saveAndRefreshWidgets(freshSnapshot);
      }
      _loadSource = selectedIsToday ? 'backend' : 'backend (date browse)';
      _activeProvider = backendEvents.isEmpty
          ? provider
          : backendEvents.first.provider;
      _lastGoodSnapshot = freshSnapshot;
      return freshSnapshot;
    } catch (_) {
      if (!allowCacheFallback || !selectedIsToday) {
        rethrow;
      }
      // Fall through to cached/local fallback path.
    }

    final existing = await _snapshotStore.load();
    if (existing != null) {
      _loadSource = 'cache';
      _activeProvider = existing.events.isEmpty
          ? 'unknown'
          : existing.events.first.provider;
      _lastGoodSnapshot = existing;
      return existing;
    }

    final now = DateTime.now();
    final snapshot = const WidgetSnapshotBuilder().build(
      now: now,
      timezone: now.timeZoneName.isEmpty ? 'UTC' : now.timeZoneName,
      events: _sampleEvents(now),
      theme: _widgetThemeForSnapshot,
    );
    await _saveAndRefreshWidgets(snapshot);
    _loadSource = 'sample';
    _activeProvider = 'local';
    _lastGoodSnapshot = snapshot;
    return snapshot;
  }

  Future<void> _regenerateSnapshot() async {
    _startSnapshotReload(
      () => _reloadForProvider(
        _selectedProvider,
        refreshAuthStatus: false,
        allowCacheFallback: false,
      ),
    );
  }

  Future<void> _saveAndRefreshWidgets(WidgetSnapshot snapshot) async {
    await _snapshotStore.save(snapshot);
    await _widgetHostBridge.syncWidgetReadPayload(
      buildWidgetReadPayload(snapshot),
    );
    await _widgetHostBridge.refreshHomeWidgets();
  }

  Future<void> _onProviderChanged(String? value) async {
    if (value == null || value == _selectedProvider) {
      return;
    }

    setState(() {
      _selectedProvider = value;
      _googleRedirectUri = null;
    });
    _startSnapshotReload(
      () => _reloadForProvider(
        value,
        refreshAuthStatus: true,
        allowCacheFallback: false,
      ),
    );
  }

  Future<WidgetSnapshot> _reloadForProvider(
    String provider, {
    required bool refreshAuthStatus,
    required bool allowCacheFallback,
  }) async {
    if (refreshAuthStatus) {
      await _refreshProviderStatus(provider: provider, includeIdentity: true);
    }

    try {
      return await _loadOrCreateSnapshot(
        provider: provider,
        selectedDate: _selectedDate,
        allowCacheFallback: allowCacheFallback,
      );
    } catch (error) {
      if (!_isRetryableNetworkError(error)) {
        rethrow;
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));
      return _loadOrCreateSnapshot(
        provider: provider,
        selectedDate: _selectedDate,
        allowCacheFallback: allowCacheFallback,
      );
    }
  }

  void _startSnapshotReload(Future<WidgetSnapshot> Function() reloadAction) {
    if (!mounted || _snapshotReloadInFlight) {
      return;
    }
    setState(() {
      _snapshotReloadInFlight = true;
      _snapshotFuture = reloadAction().whenComplete(() {
        if (mounted) {
          setState(() {
            _snapshotReloadInFlight = false;
          });
        }
      });
    });
  }

  void _moveSelectedDate(int dayDelta) {
    final nextDate = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day + dayDelta,
    );
    setState(() {
      _selectedDate = nextDate;
    });
    _startSnapshotReload(
      () => _reloadForProvider(
        _selectedProvider,
        refreshAuthStatus: false,
        allowCacheFallback: false,
      ),
    );
  }

  void _resetSelectedDateToToday() {
    final today = DateTime.now();
    setState(() {
      _selectedDate = DateTime(today.year, today.month, today.day);
    });
    _startSnapshotReload(
      () => _reloadForProvider(
        _selectedProvider,
        refreshAuthStatus: false,
        allowCacheFallback: false,
      ),
    );
  }

  bool _isTodaySelected() {
    return _isSameCalendarDate(_selectedDate, DateTime.now());
  }

  bool _isSameCalendarDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _normalizeWidgetTheme(String raw) {
    final lowered = raw.trim().toLowerCase();
    if (lowered == 'light' || lowered == 'white') {
      return 'light';
    }
    return 'dark';
  }

  Future<void> _startGoogleAuthFlow() async {
    if (_authFlowBusy) {
      return;
    }

    setState(() {
      _authFlowBusy = true;
    });

    final i18n = context.i18n;
    try {
      final payload = await _eventsRepository.fetchGoogleAuthUrl(
        mobileCallback: BackendConfig.googleMobileCallbackUri,
      );
      _googleRedirectUri = payload.redirectUri;

      final uri = Uri.tryParse(payload.authUrl);
      if (uri == null) {
        throw FormatException(i18n.invalidGoogleAuthUrl);
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(i18n.unableToOpenBrowser)));
      } else if (mounted) {
        _startAuthStatusPolling();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(i18n.completeSignInThenRefresh)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_googleAuthStartErrorMessage(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _authFlowBusy = false;
        });
      }
    }
  }

  WidgetSnapshot _buildEmptySnapshot() {
    final now = DateTime.now();
    return const WidgetSnapshotBuilder().build(
      now: now,
      timezone: now.timeZoneName.isEmpty ? 'UTC' : now.timeZoneName,
      events: const <CalendarEvent>[],
      theme: _widgetThemeForSnapshot,
    );
  }

  Future<void> _logoutSelectedProvider({bool silent = false}) async {
    if (_logoutFlowBusy) {
      return;
    }

    setState(() {
      _logoutFlowBusy = true;
    });

    final i18n = context.i18n;
    final provider = _selectedProvider;
    try {
      await _eventsRepository.logoutProvider(provider: provider);
      await _refreshProviderStatus(provider: provider, includeIdentity: true);
      await _refreshWidgetThemeSetting();
      final emptySnapshot = _buildEmptySnapshot();
      await _saveAndRefreshWidgets(emptySnapshot);
      if (!mounted) {
        return;
      }

      setState(() {
        _providerAuthenticated = false;
        _providerAccountLabel = null;
        _providerAccountEmail = null;
        _googleRedirectUri = null;
        _lastGoodSnapshot = emptySnapshot;
        _snapshotFuture = Future<WidgetSnapshot>.value(emptySnapshot);
        _loadSource = 'signed-out';
      });

      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(i18n.providerLoggedOut(provider))),
        );
      }
    } catch (error) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(i18n.providerLogoutFailed(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _logoutFlowBusy = false;
        });
      }
    }
  }

  Future<void> _switchGoogleAccount() async {
    if (_selectedProvider != 'google') {
      return;
    }
    await _logoutSelectedProvider(silent: true);
    if (!mounted) {
      return;
    }
    await _startGoogleAuthFlow();
  }

  String _googleAuthStartErrorMessage(Object error) {
    final i18n = context.i18n;
    final backendUri = Uri.tryParse(_backendBaseUrl);
    final backendHost = backendUri?.host ?? '';
    if (error is BackendApiException) {
      return i18n.googleAuthStartFailed(error.message);
    }
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException) {
      return i18n.googleAuthBackendUnreachable(
        _backendBaseUrl,
        localBackend: _isLikelyLocalBackendHost(backendHost),
        emulatorHint: backendHost == '10.0.0.2',
      );
    }
    return i18n.googleAuthStartFailed(error.toString());
  }

  String _snapshotRefreshErrorMessage(Object error) {
    final i18n = context.i18n;
    final backendUri = Uri.tryParse(_backendBaseUrl);
    final backendHost = backendUri?.host ?? '';

    if (error is BackendApiException) {
      return i18n.refreshFailed(error.message);
    }
    if (error is TimeoutException ||
        error is SocketException ||
        error is HttpException) {
      return i18n.refreshBackendUnreachable(
        _backendBaseUrl,
        localBackend: _isLikelyLocalBackendHost(backendHost),
        emulatorHint: backendHost == '10.0.0.2',
      );
    }
    return i18n.refreshFailed(error.toString());
  }

  bool _isLikelyLocalBackendHost(String host) {
    final normalized = host.trim().toLowerCase();
    if (normalized.isEmpty ||
        normalized == 'localhost' ||
        normalized == '127.0.0.1') {
      return true;
    }
    if (normalized == '10.0.2.2' || normalized == '10.0.0.2') {
      return true;
    }
    if (normalized.startsWith('192.168.') || normalized.startsWith('10.')) {
      return true;
    }
    if (normalized.startsWith('172.')) {
      final parts = normalized.split('.');
      final second = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (second != null && second >= 16 && second <= 31) {
        return true;
      }
    }
    return false;
  }

  bool _isRetryableNetworkError(Object error) {
    return error is TimeoutException ||
        error is SocketException ||
        error is HttpException;
  }

  Future<void> _refreshAuthOnly() async {
    await _refreshAuthStatusAndMaybeReload(includeIdentity: true);
  }

  String _deepLinkSignature(Uri uri) {
    final status = (uri.queryParameters['status'] ?? '').trim().toLowerCase();
    final provider = (uri.queryParameters['provider'] ?? '')
        .trim()
        .toLowerCase();
    final message = (uri.queryParameters['message'] ?? '').trim();
    return '${uri.scheme.toLowerCase()}|${uri.host.toLowerCase()}|${uri.path.toLowerCase()}|$status|$provider|$message';
  }

  Future<void> _submitAppleCredentials() async {
    final i18n = context.i18n;
    final appleId = _appleIdController.text.trim();
    final appPassword = _applePasswordController.text.trim();
    if (appleId.isEmpty || appPassword.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(i18n.enterAppleCredentials)));
      return;
    }

    setState(() {
      _appleCredentialBusy = true;
    });

    try {
      final response = await _eventsRepository.setAppleCredentials(
        appleId: appleId,
        appPassword: appPassword,
      );
      _appleIdController.text = appleId;
      _applePasswordController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response.authenticated
                  ? i18n.appleCredentialsSavedAndAuthenticated
                  : i18n.appleCredentialsSavedVerify,
            ),
          ),
        );
      }
      await _refreshAuthStatusAndMaybeReload(includeIdentity: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(i18n.appleCredentialSaveFailed(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _appleCredentialBusy = false;
        });
      }
    }
  }

  void _startAuthStatusPolling() {
    _stopAuthStatusPolling();
    _authStatusPollAttempts = 0;
    _authStatusPollTimer = Timer.periodic(const Duration(seconds: 3), (
      timer,
    ) async {
      _authStatusPollAttempts += 1;
      final refreshed = await _refreshAuthStatusAndMaybeReload();
      if (refreshed || _authStatusPollAttempts >= 20) {
        timer.cancel();
      }
    });
  }

  void _stopAuthStatusPolling() {
    _authStatusPollTimer?.cancel();
    _authStatusPollTimer = null;
  }

  Future<bool> _refreshAuthStatusAndMaybeReload({
    bool includeIdentity = false,
  }) async {
    final inFlight = _authRefreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final refreshFuture = _performAuthStatusRefreshAndMaybeReload(
      includeIdentity: includeIdentity,
    );
    _authRefreshInFlight = refreshFuture;
    try {
      return await refreshFuture;
    } finally {
      if (identical(_authRefreshInFlight, refreshFuture)) {
        _authRefreshInFlight = null;
      }
    }
  }

  Future<bool> _performAuthStatusRefreshAndMaybeReload({
    required bool includeIdentity,
  }) async {
    final previous = _providerAuthenticated;
    await _refreshProviderStatus(
      provider: _selectedProvider,
      includeIdentity: includeIdentity,
    );

    if (!mounted) {
      return false;
    }

    final nowAuthenticated = _providerAuthenticated == true;
    if (nowAuthenticated) {
      await _markLoginLinkingOnboardingCompleted();
    }
    final needsReloadAfterAuth =
        previous != true || (_lastGoodSnapshot?.events.isEmpty ?? true);
    if (nowAuthenticated && needsReloadAfterAuth) {
      _startSnapshotReload(
        () => _reloadForProvider(
          _selectedProvider,
          refreshAuthStatus: false,
          allowCacheFallback: false,
        ),
      );
      return true;
    }

    setState(() {});
    return false;
  }

  List<CalendarEvent> _sampleEvents(DateTime now) {
    final i18n = context.i18n;
    final sampleTitle = i18n.language == AppLanguage.korean
        ? '데일리 스탠드업'
        : 'Daily Standup';
    final sampleDescription = i18n.language == AppLanguage.korean
        ? '모바일 기반 작업 킥오프'
        : 'Mobile foundation kickoff';
    return <CalendarEvent>[
      CalendarEvent(
        id: 'sample-1',
        title: sampleTitle,
        description: sampleDescription,
        startTime: now.add(const Duration(minutes: 15)),
        endTime: now.add(const Duration(minutes: 45)),
        allDay: false,
        colorHex: '#3A86FF',
        provider: 'local',
      ),
    ];
  }

  Future<void> _openLoginLinkingPage() async {
    await _refreshProviderStatus(
      provider: _selectedProvider,
      includeIdentity: true,
    );
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LoginLinkingPage(
          activeProvider: _activeProvider,
          selectedProvider: _selectedProvider,
          providers: _providers,
          providerAuthenticated: _providerAuthenticated,
          providerAccountLabel: _providerAccountLabel,
          providerAccountEmail: _providerAccountEmail,
          authFlowBusy: _authFlowBusy,
          logoutBusy: _logoutFlowBusy,
          googleRedirectUri: _googleRedirectUri,
          appleCredentialBusy: _appleCredentialBusy,
          appleIdController: _appleIdController,
          applePasswordController: _applePasswordController,
          onProviderChanged: _onProviderChanged,
          onStartGoogleAuth: _startGoogleAuthFlow,
          onSwitchGoogleAccount: _switchGoogleAccount,
          onSubmitAppleCredentials: _submitAppleCredentials,
          onLogoutProvider: () => unawaited(_logoutSelectedProvider()),
          onRefreshAuthOnly: _refreshAuthOnly,
        ),
      ),
    );

    await _refreshProviderStatus(
      provider: _selectedProvider,
      includeIdentity: true,
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openEventToolsPage() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventToolsPage(
          repository: _eventsRepository,
          provider: _selectedProvider,
          onCreated: _handleNaturalEventCreated,
        ),
      ),
    );
  }

  void _handleNaturalEventCreated(DateTime createdStart) {
    final normalizedDate = DateTime(
      createdStart.year,
      createdStart.month,
      createdStart.day,
    );
    if (mounted && !_isSameCalendarDate(_selectedDate, normalizedDate)) {
      setState(() {
        _selectedDate = normalizedDate;
      });
    }
    _startSnapshotReload(
      () => _reloadForProvider(
        _selectedProvider,
        refreshAuthStatus: false,
        allowCacheFallback: false,
      ),
    );
  }

  Future<void> _openBriefingPage() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BriefingPage(
          repository: _eventsRepository,
          provider: _selectedProvider,
        ),
      ),
    );
  }

  Future<WidgetSnapshot> _reloadSnapshotForScreenSaver() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!_isSameCalendarDate(_selectedDate, today) && mounted) {
      setState(() {
        _selectedDate = today;
      });
    }

    final snapshot = await _reloadForProvider(
      _selectedProvider,
      refreshAuthStatus: false,
      allowCacheFallback: true,
    );
    if (mounted) {
      setState(() {
        _lastGoodSnapshot = snapshot;
        _snapshotFuture = Future<WidgetSnapshot>.value(snapshot);
      });
    }
    return snapshot;
  }

  Future<WidgetSnapshot> _resolveScreenSaverInitialSnapshot({
    required bool preferFastEntry,
  }) async {
    if (!preferFastEntry) {
      return _reloadSnapshotForScreenSaver();
    }

    final inMemory = _lastGoodSnapshot;
    if (inMemory != null) {
      return inMemory;
    }

    final cached = await _snapshotStore.load();
    if (cached != null) {
      _lastGoodSnapshot = cached;
      _loadSource = 'cache';
      if (mounted) {
        setState(() {
          _snapshotFuture = Future<WidgetSnapshot>.value(cached);
        });
      }
      return cached;
    }

    return _reloadSnapshotForScreenSaver();
  }

  Future<void> _openClockScreenSaverPage({
    bool preferFastEntry = false,
    bool instantTransition = false,
  }) async {
    if (_screenSaverRouteOpen) {
      return;
    }
    _screenSaverRouteOpen = true;

    try {
      WidgetSnapshot initialSnapshot;
      try {
        initialSnapshot = await _resolveScreenSaverInitialSnapshot(
          preferFastEntry: preferFastEntry,
        );
      } catch (error) {
        final fallback = _lastGoodSnapshot;
        if (fallback == null) {
          if (mounted) {
            final i18n = context.i18n;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(i18n.refreshFailed('$error'))),
            );
          }
          return;
        }
        initialSnapshot = fallback;
      }

      if (!mounted) {
        return;
      }
      final route = instantTransition
          ? PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (_, _, _) => ClockScreenSaverPage(
                initialSnapshot: initialSnapshot,
                reloadSnapshot: _reloadSnapshotForScreenSaver,
                currentLoadSource: () => _loadSource,
                showBottomInfoPanel: _screenSaverBottomPanelVisible,
                enableEventDetailBottomSheet:
                    _labsEventDetailBottomSheetEnabled,
              ),
            )
          : MaterialPageRoute<void>(
              builder: (_) => ClockScreenSaverPage(
                initialSnapshot: initialSnapshot,
                reloadSnapshot: _reloadSnapshotForScreenSaver,
                currentLoadSource: () => _loadSource,
                showBottomInfoPanel: _screenSaverBottomPanelVisible,
                enableEventDetailBottomSheet:
                    _labsEventDetailBottomSheetEnabled,
              ),
            );
      await Navigator.of(context).push(route);
    } finally {
      _screenSaverRouteOpen = false;
    }
  }

  void _onBottomNavDestinationSelected(int index) {
    if (index == _selectedBottomNavIndex) {
      return;
    }

    final switchedFromSettings = _selectedBottomNavIndex == _settingsTabIndex;
    setState(() {
      _selectedBottomNavIndex = index;
    });

    if (switchedFromSettings && index == _clockTabIndex) {
      unawaited(_syncClockSnapshotAfterSettings());
    }
  }

  Future<void> _syncClockSnapshotAfterSettings() async {
    await _refreshWidgetThemeSetting(force: true);
    if (!mounted) {
      return;
    }
    _regenerateSnapshot();
  }

  Future<void> _openPermissionStatusDialog() {
    return showDialog<void>(
      context: context,
      builder: (_) => _PermissionStatusDialog(
        widgetHostBridge: _widgetHostBridge,
        lockScreenAutoModeEnabled: _lockScreenAutoModeEnabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_startupScreenSaverPending) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final i18n = context.i18n;
    final isClockTab = _selectedBottomNavIndex == _clockTabIndex;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B0F19), Color(0xFF000000)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(isClockTab ? i18n.appTitle : i18n.settingsTitle),
      ),
      body: isClockTab
          ? _buildClockTabBody(context, i18n, pageGradient)
          : _buildSettingsTabBody(context, pageGradient),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedBottomNavIndex,
        onDestinationSelected: _onBottomNavDestinationSelected,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.watch_later_outlined),
            selectedIcon: const Icon(Icons.watch_later),
            label: i18n.clockTabLabel,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: i18n.settingsAction,
          ),
        ],
      ),
    );
  }

  Widget _buildClockTabBody(
    BuildContext context,
    AppI18n i18n,
    Gradient pageGradient,
  ) {
    return Container(
      decoration: BoxDecoration(gradient: pageGradient),
      child: FutureBuilder<WidgetSnapshot>(
        future: _snapshotFuture,
        builder: (context, snapshotState) {
          final effectiveSnapshot = snapshotState.data ?? _lastGoodSnapshot;
          if (snapshotState.hasError && effectiveSnapshot == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_snapshotRefreshErrorMessage(snapshotState.error!)),
              ),
            );
          }

          if (effectiveSnapshot == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final snapshot = effectiveSnapshot;
          final reloadError = snapshotState.hasError
              ? _snapshotRefreshErrorMessage(snapshotState.error!)
              : null;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (reloadError != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      reloadError,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              AnalogClockCard(
                snapshot: snapshot,
                loadSource: _loadSource,
                onRefresh: _regenerateSnapshot,
                selectedDate: _selectedDate,
                isTodaySelected: _isTodaySelected(),
                onPreviousDate: () => _moveSelectedDate(-1),
                onNextDate: () => _moveSelectedDate(1),
                onResetToday: _resetSelectedDateToToday,
                isLoading: _snapshotReloadInFlight,
                enableEventDetailBottomSheet:
                    _labsEventDetailBottomSheetEnabled,
              ),
              const SizedBox(height: 12),
              _buildQuickActionsCard(context, i18n),
              const SizedBox(height: 12),
              _buildLockAutoModeStatusCard(context, i18n),
              const SizedBox(height: 12),
              _buildTodaySummaryCard(context, i18n, snapshot),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSettingsTabBody(BuildContext context, Gradient pageGradient) {
    final i18n = context.i18n;
    return Container(
      decoration: BoxDecoration(gradient: pageGradient),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildLockAutoModeCard(context, i18n),
          const SizedBox(height: 12),
          _buildScreenSaverSettingsCard(context, i18n),
          const SizedBox(height: 12),
          SettingsPanel(
            repository: _eventsRepository,
            provider: _selectedProvider,
            currentProvider: () => _selectedProvider,
            providerAuthenticated: _providerAuthenticated,
            providerAccountLabel: _providerAccountLabel,
            providerAccountEmail: _providerAccountEmail,
            logoutBusy: _logoutFlowBusy,
            onOpenLoginLinking: _openLoginLinkingPage,
            onLogoutProvider: _logoutSelectedProvider,
            labsEventDetailBottomSheetEnabled:
                _labsEventDetailBottomSheetEnabled,
            onLabsEventDetailBottomSheetChanged:
                _onLabsEventDetailBottomSheetChanged,
          ),
          const SizedBox(height: 12),
          _buildPermissionStatusCard(context, i18n),
          const SizedBox(height: 12),
          ColorSchemaEditor(
            repository: _eventsRepository,
            provider: _selectedProvider,
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionStatusCard(BuildContext context, AppI18n i18n) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              i18n.permissionStatusCardTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              i18n.permissionStatusCardDescription,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => unawaited(_openPermissionStatusDialog()),
              icon: const Icon(Icons.verified_user_outlined),
              label: Text(i18n.permissionStatusDialogTitle),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockAutoModeCard(BuildContext context, AppI18n i18n) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              i18n.lockScreenAutoModeCardTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              i18n.lockScreenAutoModeCardDescription,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_lockScreenAutoModeNotificationBlocked) ...[
              const SizedBox(height: 8),
              Text(
                i18n.lockScreenAutoModeBlockedByPermission,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _lockScreenAutoModeToggleInFlight
                  ? null
                  : () => unawaited(_toggleLockScreenAutoMode()),
              icon: _lockScreenAutoModeToggleInFlight
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _lockScreenAutoModeEnabled
                          ? Icons.lock_open_rounded
                          : Icons.lock_outline,
                    ),
              label: Text(
                _lockScreenAutoModeEnabled
                    ? i18n.lockScreenAutoModeDisableAction
                    : i18n.lockScreenAutoModeEnableAction,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => unawaited(_openPermissionStatusDialog()),
              icon: const Icon(Icons.verified_user_outlined),
              label: Text(i18n.permissionStatusDialogTitle),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScreenSaverSettingsCard(BuildContext context, AppI18n i18n) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              i18n.screenSaverSettingsCardTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              i18n.screenSaverSettingsCardDescription,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              value: _screenSaverBottomPanelVisible,
              contentPadding: EdgeInsets.zero,
              title: Text(i18n.screenSaverBottomPanelToggleLabel),
              subtitle: Text(i18n.screenSaverBottomPanelToggleHint),
              onChanged: _onScreenSaverBottomPanelVisibleChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockAutoModeStatusCard(BuildContext context, AppI18n i18n) {
    final statusLabel = !_lockScreenAutoModeEnabled
        ? i18n.permissionStatusValueDisabled
        : _lockScreenAutoModeNotificationBlocked
        ? i18n.lockScreenAutoModeBlockedByPermissionShort
        : i18n.permissionStatusValueEnabled;
    final statusIcon = !_lockScreenAutoModeEnabled
        ? Icons.lock_outline
        : _lockScreenAutoModeNotificationBlocked
        ? Icons.error_outline
        : Icons.lock_open_rounded;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(statusIcon, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    i18n.lockScreenAutoModeCardTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(statusLabel, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              i18n.lockScreenAutoModeQuickAccessHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _selectedBottomNavIndex = _settingsTabIndex;
                });
              },
              icon: const Icon(Icons.settings_outlined),
              label: Text(i18n.lockScreenAutoModeGoToSettingsAction),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard(BuildContext context, AppI18n i18n) {
    final actions = <_QuickActionConfig>[
      _QuickActionConfig(
        icon: Icons.auto_awesome,
        label: i18n.eventToolsAction,
        onPressed: () => unawaited(_openEventToolsPage()),
      ),
      _QuickActionConfig(
        icon: Icons.article_outlined,
        label: i18n.briefingAction,
        onPressed: () => unawaited(_openBriefingPage()),
      ),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              i18n.quickActionsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 10.0;
                final buttonWidth = (constraints.maxWidth - gap) / 2;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: actions
                      .map(
                        (action) => SizedBox(
                          width: buttonWidth,
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            onPressed: action.onPressed,
                            icon: Icon(action.icon),
                            label: Text(action.label),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodaySummaryCard(
    BuildContext context,
    AppI18n i18n,
    WidgetSnapshot snapshot,
  ) {
    final previewEvents = snapshot.events.take(3).toList();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              i18n.todayAtGlanceTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SummaryChip(
                  icon: Icons.cloud_outlined,
                  label: i18n.providerValue(_selectedProvider),
                ),
                _SummaryChip(
                  icon: Icons.verified_user_outlined,
                  label: i18n.authenticatedSummary(_providerAuthenticated),
                ),
                _SummaryChip(
                  icon: Icons.person_outline,
                  label: i18n.accountSummary(_providerAccountLabel),
                ),
                _SummaryChip(
                  icon: Icons.event_available_outlined,
                  label: i18n.eventsSummary(snapshot.events.length),
                ),
                _SummaryChip(
                  icon: Icons.timelapse_outlined,
                  label: i18n.segmentsSummary(snapshot.segments.length),
                ),
              ],
            ),
            const Divider(height: 20),
            if (previewEvents.isEmpty)
              Text(
                i18n.eventsSummary(0),
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              ...previewEvents.map(
                (event) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _parseHexColor(event.colorHex),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatEventPreviewTime(i18n, event),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatEventPreviewTime(AppI18n i18n, CalendarEvent event) {
    if (event.allDay) {
      return i18n.allDayLabel;
    }
    final start =
        '${event.startTime.hour.toString().padLeft(2, '0')}:${event.startTime.minute.toString().padLeft(2, '0')}';
    final end =
        '${event.endTime.hour.toString().padLeft(2, '0')}:${event.endTime.minute.toString().padLeft(2, '0')}';
    return start == end ? start : '$start-$end';
  }

  Color _parseHexColor(String hexValue) {
    final cleaned = hexValue.trim().replaceFirst('#', '');
    final parsed = int.tryParse(cleaned, radix: 16);
    if (parsed == null || cleaned.length != 6) {
      return const Color(0xFF64748B);
    }
    return Color(0xFF000000 | parsed);
  }
}

class _QuickActionConfig {
  const _QuickActionConfig({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _PermissionStatusDialog extends StatefulWidget {
  const _PermissionStatusDialog({
    required this.widgetHostBridge,
    required this.lockScreenAutoModeEnabled,
  });

  final WidgetHostBridge widgetHostBridge;
  final bool lockScreenAutoModeEnabled;

  @override
  State<_PermissionStatusDialog> createState() =>
      _PermissionStatusDialogState();
}

class _PermissionStatusDialogState extends State<_PermissionStatusDialog> {
  bool _loading = true;
  bool _openingSettings = false;
  bool _notificationRuntimeRequired = false;
  bool _notificationGranted = false;
  bool _batteryOptimizationIgnored = false;
  bool _fullScreenIntentAllowed = false;
  bool _overlayPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!Platform.isAndroid) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
      });
      return;
    }

    final runtimeRequired = await widget.widgetHostBridge
        .isNotificationPermissionRuntimeRequired();
    final notificationGranted = await widget.widgetHostBridge
        .checkNotificationPermission();
    final batteryIgnored = await widget.widgetHostBridge
        .isIgnoringBatteryOptimizations();
    final fullScreenIntentAllowed = await widget.widgetHostBridge
        .canUseFullScreenIntent();
    final overlayPermissionGranted = await widget.widgetHostBridge
        .canDrawOverlays();
    if (!mounted) {
      return;
    }
    setState(() {
      _notificationRuntimeRequired = runtimeRequired;
      _notificationGranted = notificationGranted;
      _batteryOptimizationIgnored = batteryIgnored;
      _fullScreenIntentAllowed = fullScreenIntentAllowed;
      _overlayPermissionGranted = overlayPermissionGranted;
      _loading = false;
    });
  }

  Future<void> _openSettings(
    Future<bool> Function() action,
    String targetLabel,
  ) async {
    if (_openingSettings) {
      return;
    }
    setState(() {
      _openingSettings = true;
    });

    final opened = await action();
    if (!mounted) {
      return;
    }
    if (!opened) {
      final i18n = context.i18n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(i18n.permissionStatusOpenSettingsFailed(targetLabel)),
        ),
      );
    }
    await _refresh();
    if (mounted) {
      setState(() {
        _openingSettings = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return AlertDialog(
      title: Text(i18n.permissionStatusDialogTitle),
      content: SizedBox(
        width: 360,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i18n.permissionStatusDialogDescription,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  _PermissionStatusRow(
                    label: i18n.permissionStatusAutoModeLabel,
                    value: widget.lockScreenAutoModeEnabled
                        ? i18n.permissionStatusValueEnabled
                        : i18n.permissionStatusValueDisabled,
                    icon: widget.lockScreenAutoModeEnabled
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked,
                  ),
                  _PermissionStatusRow(
                    label: i18n.permissionStatusNotificationLabel,
                    value: !_notificationRuntimeRequired
                        ? i18n.permissionStatusValueNotRequired
                        : _notificationGranted
                        ? i18n.permissionStatusValueGranted
                        : i18n.permissionStatusValueNotGranted,
                    icon: !_notificationRuntimeRequired
                        ? Icons.info_outline
                        : _notificationGranted
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                  ),
                  _PermissionStatusRow(
                    label: i18n.permissionStatusBatteryOptimizationLabel,
                    value: _batteryOptimizationIgnored
                        ? i18n.permissionStatusValueExempted
                        : i18n.permissionStatusValueNotExempted,
                    icon: _batteryOptimizationIgnored
                        ? Icons.battery_charging_full
                        : Icons.battery_alert_outlined,
                  ),
                  _PermissionStatusRow(
                    label: i18n.permissionStatusFullScreenIntentLabel,
                    value: _fullScreenIntentAllowed
                        ? i18n.permissionStatusValueAllowed
                        : i18n.permissionStatusValueBlocked,
                    icon: _fullScreenIntentAllowed
                        ? Icons.fullscreen
                        : Icons.fullscreen_exit,
                  ),
                  _PermissionStatusRow(
                    label: i18n.permissionStatusOverlayPermissionLabel,
                    value: _overlayPermissionGranted
                        ? i18n.permissionStatusValueAllowed
                        : i18n.permissionStatusValueBlocked,
                    icon: _overlayPermissionGranted
                        ? Icons.layers
                        : Icons.layers_clear,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _openingSettings
                        ? null
                        : () => unawaited(
                            _openSettings(
                              widget.widgetHostBridge.openNotificationSettings,
                              i18n.permissionStatusNotificationLabel,
                            ),
                          ),
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: Text(
                      i18n.permissionStatusOpenNotificationSettingsAction,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _openingSettings
                        ? null
                        : () => unawaited(
                            _openSettings(
                              widget
                                  .widgetHostBridge
                                  .openBatteryOptimizationSettings,
                              i18n.permissionStatusBatteryOptimizationLabel,
                            ),
                          ),
                    icon: const Icon(Icons.battery_saver_outlined),
                    label: Text(i18n.permissionStatusOpenBatterySettingsAction),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _openingSettings
                        ? null
                        : () => unawaited(
                            _openSettings(
                              widget
                                  .widgetHostBridge
                                  .openFullScreenIntentSettings,
                              i18n.permissionStatusFullScreenIntentLabel,
                            ),
                          ),
                    icon: const Icon(Icons.fullscreen),
                    label: Text(
                      i18n.permissionStatusOpenFullScreenIntentSettingsAction,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _openingSettings
                        ? null
                        : () => unawaited(
                            _openSettings(
                              widget
                                  .widgetHostBridge
                                  .openOverlayPermissionSettings,
                              i18n.permissionStatusOverlayPermissionLabel,
                            ),
                          ),
                    icon: const Icon(Icons.layers_outlined),
                    label: Text(i18n.permissionStatusOpenOverlaySettingsAction),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _openingSettings
                        ? null
                        : () => unawaited(
                            _openSettings(
                              widget.widgetHostBridge.openAppPermissionSettings,
                              i18n.permissionStatusCardTitle,
                            ),
                          ),
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: Text(
                      i18n.permissionStatusOpenAppPermissionSettingsAction,
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _loading || _openingSettings
              ? null
              : () => unawaited(_refresh()),
          child: Text(i18n.permissionStatusRefreshAction),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(i18n.closeAction),
        ),
      ],
    );
  }
}

class _PermissionStatusRow extends StatelessWidget {
  const _PermissionStatusRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: 8),
          Text(value, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
