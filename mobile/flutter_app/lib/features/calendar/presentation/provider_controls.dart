import 'package:flutter/material.dart';

class ProviderControlsWidget extends StatelessWidget {
  const ProviderControlsWidget({
    super.key,
    required this.activeProvider,
    required this.selectedProvider,
    required this.providers,
    required this.providerAuthenticated,
    required this.authFlowBusy,
    required this.googleRedirectUri,
    required this.appleCredentialBusy,
    required this.appleIdController,
    required this.applePasswordController,
    required this.onProviderChanged,
    required this.onStartGoogleAuth,
    required this.onSubmitAppleCredentials,
    required this.onRefreshAuthOnly,
  });

  final String activeProvider;
  final String selectedProvider;
  final List<String> providers;
  final bool? providerAuthenticated;
  final bool authFlowBusy;
  final String? googleRedirectUri;
  final bool appleCredentialBusy;
  final TextEditingController appleIdController;
  final TextEditingController applePasswordController;

  final ValueChanged<String?> onProviderChanged;
  final VoidCallback onStartGoogleAuth;
  final VoidCallback onSubmitAppleCredentials;
  final VoidCallback onRefreshAuthOnly;

  @override
  Widget build(BuildContext context) {
    final authResolved = providerAuthenticated != null;
    final authOk = providerAuthenticated == true;
    final authLabel = !authResolved
        ? 'unknown'
        : (authOk ? 'authenticated' : 'not authenticated');
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
            Text('Provider & Auth Controls',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Provider: '),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: selectedProvider,
                  items: providers
                      .map((provider) => DropdownMenuItem<String>(
                            value: provider,
                            child: Text(provider),
                          ))
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
            if (selectedProvider == 'google' && providerAuthenticated != true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.icon(
                  onPressed: authFlowBusy ? null : onStartGoogleAuth,
                  icon: const Icon(Icons.login),
                  label: Text(
                    authFlowBusy
                        ? 'Starting Google sign-in...'
                        : 'Start Google Sign-in',
                  ),
                ),
              ),
            if (selectedProvider == 'google' && providerAuthenticated != true)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Use external browser sign-in, then return to app. '
                  'Auth status refreshes automatically on resume.',
                ),
              ),
            if (selectedProvider == 'apple' && providerAuthenticated != true)
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
                        controller: appleIdController,
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
                        controller: applePasswordController,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'App-specific password',
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed:
                            appleCredentialBusy ? null : onSubmitAppleCredentials,
                        icon: const Icon(Icons.lock_open),
                        label: Text(
                          appleCredentialBusy
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
            if (googleRedirectUri != null && googleRedirectUri!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Redirect URI: $googleRedirectUri'),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRefreshAuthOnly,
              icon: const Icon(Icons.verified_user),
              label: const Text('Refresh auth status'),
            ),
            const SizedBox(height: 8),
            Text('Active Provider: $activeProvider'),
          ],
        ),
      ),
    );
  }
}
