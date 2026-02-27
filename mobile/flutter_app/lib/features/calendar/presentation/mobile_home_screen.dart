import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/backend_config.dart';
import '../../../core/storage/widget_snapshot_store.dart';
import '../../../integrations/backend_api/api_client.dart';
import '../../../integrations/widget_host/widget_host_bridge.dart';
import '../application/widget_snapshot_builder.dart';
import '../data/calendar_events_repository.dart';
import '../domain/models/calendar_event.dart';
import '../domain/models/widget_snapshot.dart';
import '../../briefing/presentation/briefing_panel.dart';
import 'provider_controls.dart';
import 'event_create_form.dart';
import 'natural_input_form.dart';
import '../../settings/presentation/settings_panel.dart';
import '../../settings/presentation/color_schema_editor.dart';

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen>
    with WidgetsBindingObserver {
  static const Duration _deepLinkDedupWindow = Duration(seconds: 5);
  static const Duration _resumeRefreshDebounce = Duration(seconds: 2);

  late final WidgetSnapshotStore _snapshotStore;
  late final WidgetHostBridge _widgetHostBridge;
  late final CalendarEventsRepository _eventsRepository;
  late final String _backendBaseUrl;
  late Future<WidgetSnapshot> _snapshotFuture;
  String _loadSource = 'cache';
  String _activeProvider = 'google';
  String _selectedProvider = 'google';
  List<String> _providers = const <String>['google', 'apple'];
  bool? _providerAuthenticated;
  bool _authFlowBusy = false;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _snapshotStore = FileWidgetSnapshotStore();
    _widgetHostBridge = WidgetHostBridge();
    _backendBaseUrl = BackendConfig.resolveBaseUrl();
    final apiClient = BackendApiClient(baseUrl: _backendBaseUrl);
    _eventsRepository = CalendarEventsRepository(apiClient: apiClient);
    _snapshotFuture = _bootstrapLoad();
    _initDeepLinkHandling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAuthStatusPolling();
    _deepLinkSubscription?.cancel();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isNotEmpty
                ? message
                : (status == 'success'
                      ? 'Google authentication completed.'
                      : 'Google authentication failed.'),
          ),
        ),
      );
    }

    await _refreshAuthStatusAndMaybeReload();
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
  }

  Future<WidgetSnapshot> _bootstrapLoad() async {
    await _loadProvidersAndStatus();
    return _loadOrCreateSnapshot(provider: _selectedProvider);
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

    await _refreshProviderStatus(provider: _selectedProvider);
  }

  Future<void> _refreshProviderStatus({required String provider}) async {
    try {
      final status = await _eventsRepository.fetchProviderStatus(
        provider: provider,
      );
      _providerAuthenticated = status.authenticated;
      _activeProvider = status.provider;
    } catch (_) {
      _providerAuthenticated = null;
      _activeProvider = provider;
    }
  }

  Future<WidgetSnapshot> _loadOrCreateSnapshot({
    required String provider,
  }) async {
    try {
      final backendEvents = await _eventsRepository.fetchTodayEvents(
        provider: provider,
      );
      final now = DateTime.now();
      final freshSnapshot = const WidgetSnapshotBuilder().build(
        now: now,
        timezone: now.timeZoneName.isEmpty ? 'UTC' : now.timeZoneName,
        events: backendEvents,
      );
      await _saveAndRefreshWidgets(freshSnapshot);
      _loadSource = 'backend';
      _activeProvider = backendEvents.isEmpty
          ? provider
          : backendEvents.first.provider;
      return freshSnapshot;
    } catch (_) {
      // Fall through to cached/local fallback path.
    }

    final existing = await _snapshotStore.load();
    if (existing != null) {
      _loadSource = 'cache';
      _activeProvider = existing.events.isEmpty
          ? 'unknown'
          : existing.events.first.provider;
      return existing;
    }

    final now = DateTime.now();
    final snapshot = const WidgetSnapshotBuilder().build(
      now: now,
      timezone: now.timeZoneName.isEmpty ? 'UTC' : now.timeZoneName,
      events: _sampleEvents(now),
    );
    await _saveAndRefreshWidgets(snapshot);
    _loadSource = 'sample';
    _activeProvider = 'local';
    return snapshot;
  }

  Future<void> _regenerateSnapshot() async {
    if (mounted) {
      setState(() {
        _snapshotFuture = _reloadForProvider(_selectedProvider);
      });
    }
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
      _snapshotFuture = _reloadForProvider(value);
    });
  }

  Future<WidgetSnapshot> _reloadForProvider(String provider) async {
    await _refreshProviderStatus(provider: provider);
    return _loadOrCreateSnapshot(provider: provider);
  }

  Future<void> _startGoogleAuthFlow() async {
    if (_authFlowBusy) {
      return;
    }

    setState(() {
      _authFlowBusy = true;
    });

    try {
      final payload = await _eventsRepository.fetchGoogleAuthUrl(
        mobileCallback: BackendConfig.googleMobileCallbackUri,
      );
      _googleRedirectUri = payload.redirectUri;

      final uri = Uri.tryParse(payload.authUrl);
      if (uri == null) {
        throw const FormatException('Invalid Google auth url');
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open browser automatically.'),
          ),
        );
      } else if (mounted) {
        _startAuthStatusPolling();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Complete sign-in in browser, then tap Refresh auth status.',
            ),
          ),
        );
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

  String _googleAuthStartErrorMessage(Object error) {
    if (error is BackendApiException) {
      return 'Google auth start failed: ${error.message}';
    }
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException) {
      return 'Google auth start failed: backend unreachable ($_backendBaseUrl). '
          'For physical Android, run adb reverse tcp:8000 tcp:8000 or set --dart-define=BACKEND_BASE_URL.';
    }
    return 'Google auth start failed: $error';
  }

  Future<void> _refreshAuthOnly() async {
    await _refreshAuthStatusAndMaybeReload();
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
    final appleId = _appleIdController.text.trim();
    final appPassword = _applePasswordController.text.trim();
    if (appleId.isEmpty || appPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter Apple ID and app-specific password.'),
        ),
      );
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
                  ? 'Apple credentials saved and authenticated.'
                  : 'Apple credentials saved. Verify auth status.',
            ),
          ),
        );
      }
      await _refreshAuthStatusAndMaybeReload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Apple credential save failed: $error')),
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

  Future<bool> _refreshAuthStatusAndMaybeReload() async {
    final inFlight = _authRefreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final refreshFuture = _performAuthStatusRefreshAndMaybeReload();
    _authRefreshInFlight = refreshFuture;
    try {
      return await refreshFuture;
    } finally {
      if (identical(_authRefreshInFlight, refreshFuture)) {
        _authRefreshInFlight = null;
      }
    }
  }

  Future<bool> _performAuthStatusRefreshAndMaybeReload() async {
    final previous = _providerAuthenticated;
    await _refreshProviderStatus(provider: _selectedProvider);

    if (!mounted) {
      return false;
    }

    final nowAuthenticated = _providerAuthenticated == true;
    if (previous != true && nowAuthenticated) {
      setState(() {
        _snapshotFuture = _reloadForProvider(_selectedProvider);
      });
      return true;
    }

    setState(() {});
    return false;
  }

  List<CalendarEvent> _sampleEvents(DateTime now) {
    return <CalendarEvent>[
      CalendarEvent(
        id: 'sample-1',
        title: 'Daily Standup',
        description: 'Mobile foundation kickoff',
        startTime: now.add(const Duration(minutes: 15)),
        endTime: now.add(const Duration(minutes: 45)),
        allDay: false,
        colorHex: '#3A86FF',
        provider: 'local',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Analog Mobile')),
      body: FutureBuilder<WidgetSnapshot>(
        future: _snapshotFuture,
        builder: (context, snapshotState) {
          if (snapshotState.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Snapshot load failed: ${snapshotState.error}'),
              ),
            );
          }

          if (!snapshotState.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final snapshot = snapshotState.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Phase 1 foundation initialized',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text('Date: ${snapshot.date}'),
              Text('Timezone: ${snapshot.timezone}'),
              Text('Loaded from: $_loadSource'),
              const SizedBox(height: 8),
              ProviderControlsWidget(
                activeProvider: _activeProvider,
                selectedProvider: _selectedProvider,
                providers: _providers,
                providerAuthenticated: _providerAuthenticated,
                authFlowBusy: _authFlowBusy,
                googleRedirectUri: _googleRedirectUri,
                appleCredentialBusy: _appleCredentialBusy,
                appleIdController: _appleIdController,
                applePasswordController: _applePasswordController,
                onProviderChanged: _onProviderChanged,
                onStartGoogleAuth: _startGoogleAuthFlow,
                onSubmitAppleCredentials: _submitAppleCredentials,
                onRefreshAuthOnly: _refreshAuthOnly,
              ),
              SettingsPanel(repository: _eventsRepository),
              EventCreateForm(
                repository: _eventsRepository,
                provider: _selectedProvider,
                onCreated: _regenerateSnapshot,
              ),
              NaturalInputForm(
                repository: _eventsRepository,
                provider: _selectedProvider,
                onCreated: _regenerateSnapshot,
              ),
              BriefingPanel(
                repository: _eventsRepository,
                provider: _selectedProvider,
              ),
              ColorSchemaEditor(
                repository: _eventsRepository,
                provider: _selectedProvider,
              ),
              Text('Events loaded: ${snapshot.events.length}'),
              Text('Clock segments: ${snapshot.segments.length}'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _regenerateSnapshot,
                icon: const Icon(Icons.update),
                label: const Text('Regenerate Snapshot'),
              ),
              const SizedBox(height: 20),
              const Text(
                'Next: integrate native calendar adapters and '
                'bridge snapshot storage into iOS/Android home widgets.',
              ),
            ],
          );
        },
      ),
    );
  }
}
