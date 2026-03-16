import 'json_contract.dart';

class ProviderStatusDto {
  const ProviderStatusDto({
    required this.provider,
    required this.authenticated,
    this.accountLabel,
    this.accountEmail,
  });

  final String provider;
  final bool authenticated;
  final String? accountLabel;
  final String? accountEmail;

  factory ProviderStatusDto.fromJson(Map<String, dynamic> json) {
    return ProviderStatusDto(
      provider: requireNonEmptyString(json, 'provider'),
      authenticated: requireBool(json, 'authenticated'),
      accountLabel: optionalString(json, 'account_label'),
      accountEmail: optionalString(json, 'account_email'),
    );
  }
}
