import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/localization/app_i18n.dart';
import '../../../core/localization/app_language.dart';
import '../../calendar/data/calendar_events_repository.dart';

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({
    super.key,
    required this.repository,
    required this.provider,
    required this.currentProvider,
    required this.providerAuthenticated,
    required this.providerAccountLabel,
    required this.providerAccountEmail,
    required this.logoutBusy,
    required this.onOpenLoginLinking,
    required this.onLogoutProvider,
    required this.labsEventDetailBottomSheetEnabled,
    required this.onLabsEventDetailBottomSheetChanged,
  });

  final CalendarEventsRepository repository;
  final String provider;
  final String Function() currentProvider;
  final bool? providerAuthenticated;
  final String? providerAccountLabel;
  final String? providerAccountEmail;
  final bool logoutBusy;
  final Future<void> Function() onOpenLoginLinking;
  final Future<void> Function() onLogoutProvider;
  final bool labsEventDetailBottomSheetEnabled;
  final ValueChanged<bool> onLabsEventDetailBottomSheetChanged;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  bool _loading = true;
  bool _saving = false;

  String _theme = 'system';
  String _widgetTheme = 'dark';
  String _languageCode = 'en';
  bool _languageInitialized = false;
  double _eventOpacity = 100;
  double _clockOpacity = 100;
  bool _briefingEnabled = true;
  bool _briefingTtsEnabled = false;
  bool _labsEventDetailBottomSheetEnabled = false;
  bool? _providerAuthenticated;
  String? _providerAccountLabel;
  String? _providerAccountEmail;
  bool _authActionBusy = false;

  @override
  void initState() {
    super.initState();
    _labsEventDetailBottomSheetEnabled =
        widget.labsEventDetailBottomSheetEnabled;
    _providerAuthenticated = widget.providerAuthenticated;
    _providerAccountLabel = widget.providerAccountLabel;
    _providerAccountEmail = widget.providerAccountEmail;
    _loadSettings();
  }

  @override
  void didUpdateWidget(covariant SettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.labsEventDetailBottomSheetEnabled !=
        widget.labsEventDetailBottomSheetEnabled) {
      _labsEventDetailBottomSheetEnabled =
          widget.labsEventDetailBottomSheetEnabled;
    }
    if (oldWidget.providerAuthenticated != widget.providerAuthenticated ||
        oldWidget.providerAccountLabel != widget.providerAccountLabel ||
        oldWidget.providerAccountEmail != widget.providerAccountEmail) {
      _providerAuthenticated = widget.providerAuthenticated;
      _providerAccountLabel = widget.providerAccountLabel;
      _providerAccountEmail = widget.providerAccountEmail;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_languageInitialized) {
      return;
    }
    _languageCode = context.languageController.language.code;
    _languageInitialized = true;
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await widget.repository.fetchSettings();
      if (mounted) {
        setState(() {
          _theme = settings.theme;
          _widgetTheme = settings.widgetTheme;
          _eventOpacity = settings.eventOpacity.toDouble().clamp(0.0, 100.0);
          _clockOpacity = settings.clockOpacity.toDouble().clamp(0.0, 100.0);
          _briefingEnabled = settings.briefingEnabled;
          _briefingTtsEnabled = settings.briefingTtsEnabled;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        final i18n = context.i18n;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(i18n.failedToLoadSettings(error))),
        );
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    final i18n = context.i18n;
    try {
      await widget.repository.updateSettings(
        theme: _theme,
        widgetTheme: _widgetTheme,
        eventOpacity: _eventOpacity.toInt(),
        clockOpacity: _clockOpacity.toInt(),
        briefingEnabled: _briefingEnabled,
        briefingTtsEnabled: _briefingTtsEnabled,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(i18n.settingsSaved)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(i18n.failedToSaveSettings(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _refreshProviderStatus({bool showError = false}) async {
    try {
      final status = await widget.repository.fetchProviderStatus(
        provider: widget.currentProvider(),
        includeIdentity: true,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _providerAuthenticated = status.authenticated;
        _providerAccountLabel = status.accountLabel;
        _providerAccountEmail = status.accountEmail;
      });
    } catch (error) {
      if (!mounted || !showError) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.i18n.refreshFailed('$error'))),
      );
    }
  }

  Future<void> _handleOpenLoginLinking() async {
    if (_authActionBusy) {
      return;
    }
    setState(() {
      _authActionBusy = true;
    });
    try {
      await widget.onOpenLoginLinking();
      await _refreshProviderStatus();
    } finally {
      if (mounted) {
        setState(() {
          _authActionBusy = false;
        });
      }
    }
  }

  Future<void> _handleLogout() async {
    if (_authActionBusy) {
      return;
    }
    setState(() {
      _authActionBusy = true;
      _providerAuthenticated = false;
      _providerAccountLabel = null;
      _providerAccountEmail = null;
    });
    try {
      await widget.onLogoutProvider();
      await _refreshProviderStatus();
    } finally {
      if (mounted) {
        setState(() {
          _authActionBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final providerAuthenticated = _providerAuthenticated;
    final providerAccountLabel = _providerAccountLabel;
    final providerAccountEmail = _providerAccountEmail;
    final logoutBusy = widget.logoutBusy || _authActionBusy;
    if (_loading) {
      return const Card(
        margin: EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              i18n.settingsTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: InputDecoration(labelText: i18n.languageLabel),
              child: DropdownButton<String>(
                value: _languageCode,
                isExpanded: true,
                items: [
                  DropdownMenuItem(value: 'en', child: Text(i18n.englishLabel)),
                  DropdownMenuItem(value: 'ko', child: Text(i18n.koreanLabel)),
                ],
                onChanged: (value) {
                  final nextCode = value ?? 'en';
                  setState(() => _languageCode = nextCode);
                  unawaited(
                    context.languageController.setLanguage(
                      AppLanguageX.fromCode(nextCode),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: InputDecoration(labelText: i18n.themeLabel),
              child: DropdownButton<String>(
                value: _theme,
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                    value: 'system',
                    child: Text(i18n.systemLabel),
                  ),
                  DropdownMenuItem(
                    value: 'light',
                    child: Text(i18n.lightLabel),
                  ),
                  DropdownMenuItem(value: 'dark', child: Text(i18n.darkLabel)),
                ],
                onChanged: (v) => setState(() => _theme = v ?? 'system'),
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: InputDecoration(labelText: i18n.widgetThemeLabel),
              child: DropdownButton<String>(
                value: _widgetTheme,
                isExpanded: true,
                items: [
                  DropdownMenuItem(value: 'dark', child: Text(i18n.darkLabel)),
                  DropdownMenuItem(
                    value: 'light',
                    child: Text(i18n.whiteLabel),
                  ),
                ],
                onChanged: (v) => setState(() => _widgetTheme = v ?? 'dark'),
              ),
            ),
            const SizedBox(height: 16),
            Text(i18n.eventOpacityLabel(_eventOpacity.toInt())),
            Slider(
              value: _eventOpacity,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (v) => setState(() => _eventOpacity = v),
            ),
            Text(i18n.clockOpacityLabel(_clockOpacity.toInt())),
            Slider(
              value: _clockOpacity,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (v) => setState(() => _clockOpacity = v),
            ),
            SwitchListTile(
              title: Text(i18n.briefingEnabledLabel),
              value: _briefingEnabled,
              onChanged: (v) => setState(() => _briefingEnabled = v),
            ),
            SwitchListTile(
              title: Text(i18n.briefingTtsEnabledLabel),
              value: _briefingTtsEnabled,
              onChanged: (v) => setState(() => _briefingTtsEnabled = v),
            ),
            const SizedBox(height: 16),
            Text(
              i18n.loginLinkingSettingsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              i18n.authenticatedSummary(providerAuthenticated),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (providerAccountLabel != null &&
                providerAccountLabel.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  i18n.signedInAccountLabel(providerAccountLabel.trim()),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (providerAccountEmail != null &&
                providerAccountEmail.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  providerAccountEmail.trim(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _authActionBusy
                  ? null
                  : () => unawaited(_handleOpenLoginLinking()),
              icon: const Icon(Icons.login),
              label: Text(
                providerAuthenticated == true
                    ? i18n.manageLoginLinkingLabel
                    : i18n.openLoginLinkingLabel,
              ),
            ),
            if (providerAuthenticated == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: logoutBusy
                      ? null
                      : () => unawaited(_handleLogout()),
                  icon: const Icon(Icons.logout),
                  label: Text(
                    logoutBusy
                        ? i18n.loggingOutProviderLabel
                        : i18n.logoutProviderLabel,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              i18n.labsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              i18n.labsDescription,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SwitchListTile(
              title: Text(i18n.labsEventDetailBottomSheetLabel),
              subtitle: Text(i18n.labsEventDetailBottomSheetHint),
              value: _labsEventDetailBottomSheetEnabled,
              onChanged: (v) {
                setState(() => _labsEventDetailBottomSheetEnabled = v);
                widget.onLabsEventDetailBottomSheetChanged(v);
              },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _saveSettings,
              icon: const Icon(Icons.save),
              label: Text(_saving ? i18n.savingLabel : i18n.saveSettingsLabel),
            ),
          ],
        ),
      ),
    );
  }
}
