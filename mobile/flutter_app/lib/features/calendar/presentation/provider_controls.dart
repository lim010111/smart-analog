import 'package:flutter/material.dart';

import '../../../core/localization/app_i18n.dart';

class ProviderControlsWidget extends StatelessWidget {
  const ProviderControlsWidget({
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
    this.showProviderSelector = true,
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
  final bool showProviderSelector;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final authResolved = providerAuthenticated != null;
    final authOk = providerAuthenticated == true;
    final authLabel = !authResolved
        ? i18n.authUnknown
        : (authOk ? i18n.authAuthenticated : i18n.authNotAuthenticated);
    final authColor = !authResolved
        ? Colors.grey
        : (authOk ? Colors.green : Colors.orange);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              i18n.providerAuthControlsTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (showProviderSelector)
              Row(
                children: [
                  Text('${i18n.providerLabel}: '),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: selectedProvider,
                    items: providers
                        .map(
                          (provider) => DropdownMenuItem<String>(
                            value: provider,
                            child: Text(provider),
                          ),
                        )
                        .toList(),
                    onChanged: onProviderChanged,
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
                      i18n.authStateLabel(authLabel),
                      style: TextStyle(
                        color: authColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (authOk)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  i18n.signedInAccountLabel(
                    providerAccountLabel?.trim().isNotEmpty == true
                        ? providerAccountLabel!.trim()
                        : i18n.accountUnknown,
                  ),
                ),
              ),
            if (authOk &&
                providerAccountEmail != null &&
                providerAccountEmail!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(providerAccountEmail!.trim()),
              ),
            if (selectedProvider == 'google' && providerAuthenticated != true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.icon(
                  onPressed: authFlowBusy ? null : onStartGoogleAuth,
                  icon: const Icon(Icons.login),
                  label: Text(
                    authFlowBusy
                        ? i18n.startingGoogleSignIn
                        : i18n.startGoogleSignIn,
                  ),
                ),
              ),
            if (selectedProvider == 'google' && providerAuthenticated == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.icon(
                  onPressed: authFlowBusy || logoutBusy
                      ? null
                      : onSwitchGoogleAccount,
                  icon: const Icon(Icons.switch_account),
                  label: Text(i18n.signInWithAnotherGoogleAccount),
                ),
              ),
            if (selectedProvider == 'google' && providerAuthenticated != true)
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(i18n.googleSignInHint),
              ),
            if (selectedProvider == 'apple' && providerAuthenticated != true)
              Card(
                margin: const EdgeInsets.only(top: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i18n.appleCredentialsTitle),
                      const SizedBox(height: 8),
                      TextField(
                        controller: appleIdController,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: i18n.appleIdLabel,
                          hintText: i18n.appleIdHint,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: applePasswordController,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: i18n.appSpecificPasswordLabel,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: appleCredentialBusy
                            ? null
                            : onSubmitAppleCredentials,
                        icon: const Icon(Icons.lock_open),
                        label: Text(
                          appleCredentialBusy
                              ? i18n.savingAppleCredentialsLabel
                              : i18n.saveAppleCredentialsLabel,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(i18n.applePasswordGuide),
                    ],
                  ),
                ),
              ),
            if (googleRedirectUri != null && googleRedirectUri!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(i18n.redirectUriLabel(googleRedirectUri!)),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRefreshAuthOnly,
              icon: const Icon(Icons.verified_user),
              label: Text(i18n.refreshAuthStatusLabel),
            ),
            if (providerAuthenticated == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: logoutBusy ? null : onLogoutProvider,
                  icon: const Icon(Icons.logout),
                  label: Text(
                    logoutBusy
                        ? i18n.loggingOutProviderLabel
                        : i18n.logoutProviderLabel,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(i18n.activeProviderLabel(activeProvider)),
          ],
        ),
      ),
    );
  }
}
