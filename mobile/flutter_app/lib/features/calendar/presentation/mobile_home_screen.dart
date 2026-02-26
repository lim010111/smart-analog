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

class _MobileHomeScreenState extends State<MobileHomeScreen> {
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

  @override
  void initState() {
    super.initState();
    _snapshotStore = FileWidgetSnapshotStore();
    final apiClient = BackendApiClient(baseUrl: BackendConfig.resolveBaseUrl());
    _eventsRepository = CalendarEventsRepository(apiClient: apiClient);
    _snapshotFuture = _bootstrapLoad();
  }

  @override
  void dispose() {
    _eventsRepository.dispose();
    super.dispose();
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
    await _refreshProviderStatus(provider: _selectedProvider);
    if (mounted) {
      setState(() {});
    }
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
              Text(
                'Auth state: ${_providerAuthenticated == null ? 'unknown' : (_providerAuthenticated! ? 'authenticated' : 'not authenticated')}',
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
