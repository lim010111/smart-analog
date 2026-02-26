import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/backend_config.dart';
import '../../../core/storage/widget_snapshot_store.dart';
import '../../../integrations/backend_api/api_client.dart';
import '../application/widget_snapshot_builder.dart';
import '../data/calendar_events_repository.dart';
import '../domain/models/calendar_event.dart';
import '../domain/models/widget_snapshot.dart';

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen>
    with WidgetsBindingObserver {
  late final WidgetSnapshotStore _snapshotStore;
  late final CalendarEventsRepository _eventsRepository;
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
  final TextEditingController _appleIdController = TextEditingController();
  final TextEditingController _applePasswordController =
      TextEditingController();
  bool _appleCredentialBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _snapshotStore = FileWidgetSnapshotStore();
    final apiClient = BackendApiClient(baseUrl: BackendConfig.resolveBaseUrl());
    _eventsRepository = CalendarEventsRepository(apiClient: apiClient);
    _snapshotFuture = _bootstrapLoad();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authStatusPollTimer?.cancel();
    _appleIdController.dispose();
    _applePasswordController.dispose();
    _eventsRepository.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }

    _refreshAuthStatusAndMaybeReload();
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
      await _snapshotStore.save(freshSnapshot);
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
    await _snapshotStore.save(snapshot);
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
      final payload = await _eventsRepository.fetchGoogleAuthUrl();
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
          SnackBar(content: Text('Google auth start failed: $error')),
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

  Future<void> _refreshAuthOnly() async {
    await _refreshAuthStatusAndMaybeReload();
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
    _authStatusPollTimer?.cancel();
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

  Future<bool> _refreshAuthStatusAndMaybeReload() async {
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
    final authResolved = _providerAuthenticated != null;
    final authOk = _providerAuthenticated == true;
    final authLabel = !authResolved
        ? 'unknown'
        : (authOk ? 'authenticated' : 'not authenticated');
    final authColor = !authResolved
        ? Colors.grey
        : (authOk ? Colors.green : Colors.orange);

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
              Row(
                children: [
                  const Text('Provider: '),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _selectedProvider,
                    items: _providers
                        .map(
                          (provider) => DropdownMenuItem<String>(
                            value: provider,
                            child: Text(provider),
                          ),
                        )
                        .toList(),
                    onChanged: _onProviderChanged,
                  ),
                ],
              ),
              Card(
                margin: const EdgeInsets.only(top: 8),
                color: authColor.withValues(alpha: 0.10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        authOk ? Icons.verified_user : Icons.warning_amber,
                        color: authColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Auth state: $authLabel',
                        style: TextStyle(
                          color: authColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_selectedProvider == 'google' &&
                  _providerAuthenticated != true)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton.icon(
                    onPressed: _authFlowBusy ? null : _startGoogleAuthFlow,
                    icon: const Icon(Icons.login),
                    label: Text(
                      _authFlowBusy
                          ? 'Starting Google sign-in...'
                          : 'Start Google Sign-in',
                    ),
                  ),
                ),
              if (_selectedProvider == 'google' &&
                  _providerAuthenticated != true)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Use external browser sign-in, then return to app. '
                    'Auth status refreshes automatically on resume.',
                  ),
                ),
              if (_selectedProvider == 'apple' &&
                  _providerAuthenticated != true)
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Apple credentials (app-specific password)'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _appleIdController,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Apple ID',
                            hintText: 'name@example.com',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _applePasswordController,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'App-specific password',
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _appleCredentialBusy
                              ? null
                              : _submitAppleCredentials,
                          icon: const Icon(Icons.lock_open),
                          label: Text(
                            _appleCredentialBusy
                                ? 'Saving Apple credentials...'
                                : 'Save Apple credentials',
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Use an Apple app-specific password (not your iCloud login password).',
                        ),
                      ],
                    ),
                  ),
                ),
              if (_googleRedirectUri != null && _googleRedirectUri!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Redirect URI: $_googleRedirectUri'),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _refreshAuthOnly,
                icon: const Icon(Icons.verified_user),
                label: const Text('Refresh auth status'),
              ),
              Text('Provider: $_activeProvider'),
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
