import 'package:flutter/material.dart';

import '../../../core/localization/app_i18n.dart';
import '../../../core/localization/app_language.dart';
import '../../briefing/presentation/briefing_panel.dart';
import '../../settings/presentation/color_schema_editor.dart';
import '../../settings/presentation/settings_panel.dart';
import '../data/calendar_events_repository.dart';
import 'natural_input_form.dart';
import 'provider_controls.dart';

class LoginLinkingPage extends StatelessWidget {
  const LoginLinkingPage({
    super.key,
    required this.activeProvider,
    required this.selectedProvider,
    required this.providers,
    required this.providerAuthenticated,
    required this.providerAccountLabel,
    required this.providerAccountEmail,
    required this.authFlowBusy,
    required this.logoutBusy,
    required this.googleRedirectUri,
    required this.appleCredentialBusy,
    required this.appleIdController,
    required this.applePasswordController,
    required this.onProviderChanged,
    required this.onStartGoogleAuth,
    required this.onSwitchGoogleAccount,
    required this.onSubmitAppleCredentials,
    required this.onLogoutProvider,
    required this.onRefreshAuthOnly,
  });

  final String activeProvider;
  final String selectedProvider;
  final List<String> providers;
  final bool? providerAuthenticated;
  final String? providerAccountLabel;
  final String? providerAccountEmail;
  final bool authFlowBusy;
  final bool logoutBusy;
  final String? googleRedirectUri;
  final bool appleCredentialBusy;
  final TextEditingController appleIdController;
  final TextEditingController applePasswordController;
  final ValueChanged<String?> onProviderChanged;
  final VoidCallback onStartGoogleAuth;
  final VoidCallback onSwitchGoogleAccount;
  final VoidCallback onSubmitAppleCredentials;
  final VoidCallback onLogoutProvider;
  final VoidCallback onRefreshAuthOnly;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return Scaffold(
      appBar: AppBar(title: Text(i18n.providerAuthPageTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ProviderControlsWidget(
            activeProvider: activeProvider,
            selectedProvider: selectedProvider,
            providers: providers,
            providerAuthenticated: providerAuthenticated,
            providerAccountLabel: providerAccountLabel,
            providerAccountEmail: providerAccountEmail,
            authFlowBusy: authFlowBusy,
            logoutBusy: logoutBusy,
            googleRedirectUri: googleRedirectUri,
            appleCredentialBusy: appleCredentialBusy,
            appleIdController: appleIdController,
            applePasswordController: applePasswordController,
            onProviderChanged: onProviderChanged,
            onStartGoogleAuth: onStartGoogleAuth,
            onSwitchGoogleAccount: onSwitchGoogleAccount,
            onSubmitAppleCredentials: onSubmitAppleCredentials,
            onLogoutProvider: onLogoutProvider,
            onRefreshAuthOnly: onRefreshAuthOnly,
          ),
        ],
      ),
    );
  }
}

class EventToolsPage extends StatelessWidget {
  const EventToolsPage({
    super.key,
    required this.repository,
    required this.provider,
    required this.onCreated,
  });

  final CalendarEventsRepository repository;
  final String provider;
  final ValueChanged<DateTime> onCreated;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return Scaffold(
      appBar: AppBar(title: Text(i18n.eventToolsPageTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NaturalInputForm(
            repository: repository,
            provider: provider,
            onCreated: onCreated,
          ),
        ],
      ),
    );
  }
}

class LoginLinkingOnboardingPage extends StatefulWidget {
  const LoginLinkingOnboardingPage({
    super.key,
    required this.activeProvider,
    required this.selectedProvider,
    required this.providers,
    required this.providerAuthenticated,
    required this.providerAccountLabel,
    required this.providerAccountEmail,
    required this.authFlowBusy,
    required this.logoutBusy,
    required this.googleRedirectUri,
    required this.appleCredentialBusy,
    required this.appleIdController,
    required this.applePasswordController,
    required this.onProviderChanged,
    required this.onStartGoogleAuth,
    required this.onSwitchGoogleAccount,
    required this.onSubmitAppleCredentials,
    required this.onLogoutProvider,
    required this.onRefreshAuthOnly,
  });

  final String activeProvider;
  final String selectedProvider;
  final List<String> providers;
  final bool? providerAuthenticated;
  final String? providerAccountLabel;
  final String? providerAccountEmail;
  final bool authFlowBusy;
  final bool logoutBusy;
  final String? googleRedirectUri;
  final bool appleCredentialBusy;
  final TextEditingController appleIdController;
  final TextEditingController applePasswordController;
  final ValueChanged<String?> onProviderChanged;
  final VoidCallback onStartGoogleAuth;
  final VoidCallback onSwitchGoogleAccount;
  final VoidCallback onSubmitAppleCredentials;
  final VoidCallback onLogoutProvider;
  final VoidCallback onRefreshAuthOnly;

  @override
  State<LoginLinkingOnboardingPage> createState() =>
      _LoginLinkingOnboardingPageState();
}

class _LoginLinkingOnboardingPageState
    extends State<LoginLinkingOnboardingPage> {
  static const int _stepLanguage = 0;
  static const int _stepProvider = 1;
  static const int _stepLogin = 2;

  int _currentStep = _stepLanguage;
  late String _onboardingProvider;

  @override
  void initState() {
    super.initState();
    _onboardingProvider = widget.providers.contains(widget.selectedProvider)
        ? widget.selectedProvider
        : (widget.providers.isEmpty ? 'google' : widget.providers.first);
  }

  void _handleOnboardingProviderChanged(String? value) {
    if (value == null || value == _onboardingProvider) {
      return;
    }

    setState(() {
      _onboardingProvider = value;
    });
    widget.onProviderChanged(value);
  }

  void _goToStep(int step) {
    final clamped = step.clamp(_stepLanguage, _stepLogin);
    if (clamped == _currentStep) {
      return;
    }
    setState(() {
      _currentStep = clamped;
    });
  }

  void _goNextStep() => _goToStep(_currentStep + 1);

  void _goPreviousStep() => _goToStep(_currentStep - 1);

  Widget _buildStepChip(BuildContext context, String label, int stepIndex) {
    final isActive = _currentStep == stepIndex;
    final isDone = _currentStep > stepIndex;
    final colorScheme = Theme.of(context).colorScheme;

    final background = isDone
        ? colorScheme.primaryContainer
        : isActive
        ? colorScheme.secondaryContainer
        : colorScheme.surfaceContainerHighest;
    final foreground = isDone
        ? colorScheme.onPrimaryContainer
        : isActive
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    final icon = isDone
        ? Icons.check_circle
        : isActive
        ? Icons.radio_button_checked
        : Icons.radio_button_unchecked;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: foreground,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageStepCard(
    BuildContext context,
    AppI18n i18n,
    AppLanguageController languageController,
  ) {
    final selectedLanguage = languageController.language;
    return Card(
      key: const ValueKey<String>('onboarding-step-language'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              i18n.onboardingLanguageStepTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            InputDecorator(
              decoration: InputDecoration(labelText: i18n.languageLabel),
              child: DropdownButton<AppLanguage>(
                value: selectedLanguage,
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                    value: AppLanguage.english,
                    child: Text(i18n.englishLabel),
                  ),
                  DropdownMenuItem(
                    value: AppLanguage.korean,
                    child: Text(i18n.koreanLabel),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  languageController.setLanguage(value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderStepCard(BuildContext context, AppI18n i18n) {
    return Card(
      key: const ValueKey<String>('onboarding-step-provider'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              i18n.onboardingProviderStepTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            InputDecorator(
              decoration: InputDecoration(labelText: i18n.providerLabel),
              child: DropdownButton<String>(
                value: _onboardingProvider,
                isExpanded: true,
                items: widget.providers
                    .map(
                      (provider) => DropdownMenuItem<String>(
                        value: provider,
                        child: Text(provider),
                      ),
                    )
                    .toList(),
                onChanged: _handleOnboardingProviderChanged,
              ),
            ),
            const SizedBox(height: 8),
            Text(i18n.onboardingSelectedProviderLabel(_onboardingProvider)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginStepCard(BuildContext context, AppI18n i18n) {
    return Column(
      key: const ValueKey<String>('onboarding-step-login'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          i18n.onboardingLoginStepTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        ProviderControlsWidget(
          activeProvider: widget.activeProvider,
          selectedProvider: _onboardingProvider,
          providers: widget.providers,
          providerAuthenticated: widget.providerAuthenticated,
          providerAccountLabel: widget.providerAccountLabel,
          providerAccountEmail: widget.providerAccountEmail,
          authFlowBusy: widget.authFlowBusy,
          logoutBusy: widget.logoutBusy,
          googleRedirectUri: widget.googleRedirectUri,
          appleCredentialBusy: widget.appleCredentialBusy,
          appleIdController: widget.appleIdController,
          applePasswordController: widget.applePasswordController,
          onProviderChanged: _handleOnboardingProviderChanged,
          onStartGoogleAuth: widget.onStartGoogleAuth,
          onSwitchGoogleAccount: widget.onSwitchGoogleAccount,
          onSubmitAppleCredentials: widget.onSubmitAppleCredentials,
          onLogoutProvider: widget.onLogoutProvider,
          onRefreshAuthOnly: widget.onRefreshAuthOnly,
          showProviderSelector: false,
        ),
      ],
    );
  }

  Widget _buildCurrentStepContent(
    BuildContext context,
    AppI18n i18n,
    AppLanguageController languageController,
  ) {
    switch (_currentStep) {
      case _stepLanguage:
        return _buildLanguageStepCard(context, i18n, languageController);
      case _stepProvider:
        return _buildProviderStepCard(context, i18n);
      case _stepLogin:
        return _buildLoginStepCard(context, i18n);
      default:
        return const SizedBox.shrink();
    }
  }

  String _nextLabel(AppI18n i18n) {
    switch (_currentStep) {
      case _stepLanguage:
        return i18n.onboardingContinueToProviderLabel;
      case _stepProvider:
        return i18n.onboardingContinueToLoginLabel;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final languageController = context.languageController;
    final nextVisible = _currentStep < _stepLogin;
    final previousVisible = _currentStep > _stepLanguage;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: Text(i18n.loginLinkingOnboardingTitle)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              i18n.loginLinkingOnboardingDescription,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              i18n.loginLinkingOnboardingPendingHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStepChip(
                  context,
                  i18n.onboardingLanguageStepTitle,
                  _stepLanguage,
                ),
                _buildStepChip(
                  context,
                  i18n.onboardingProviderStepTitle,
                  _stepProvider,
                ),
                _buildStepChip(
                  context,
                  i18n.onboardingLoginStepTitle,
                  _stepLogin,
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0.03, 0),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: _buildCurrentStepContent(
                context,
                i18n,
                languageController,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (previousVisible)
                  OutlinedButton.icon(
                    onPressed: _goPreviousStep,
                    icon: const Icon(Icons.arrow_back),
                    label: Text(i18n.onboardingBackLabel),
                  ),
                const Spacer(),
                if (nextVisible)
                  FilledButton.icon(
                    onPressed: _goNextStep,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(_nextLabel(i18n)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class BriefingPage extends StatelessWidget {
  const BriefingPage({
    super.key,
    required this.repository,
    required this.provider,
  });

  final CalendarEventsRepository repository;
  final String provider;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return Scaffold(
      appBar: AppBar(title: Text(i18n.briefingPageTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [BriefingPanel(repository: repository, provider: provider)],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
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
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return Scaffold(
      appBar: AppBar(title: Text(i18n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SettingsPanel(
            repository: repository,
            provider: provider,
            currentProvider: currentProvider,
            providerAuthenticated: providerAuthenticated,
            providerAccountLabel: providerAccountLabel,
            providerAccountEmail: providerAccountEmail,
            logoutBusy: logoutBusy,
            onOpenLoginLinking: onOpenLoginLinking,
            onLogoutProvider: onLogoutProvider,
            labsEventDetailBottomSheetEnabled:
                labsEventDetailBottomSheetEnabled,
            onLabsEventDetailBottomSheetChanged:
                onLabsEventDetailBottomSheetChanged,
          ),
          ColorSchemaEditor(repository: repository, provider: provider),
        ],
      ),
    );
  }
}
