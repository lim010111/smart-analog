import 'json_contract.dart';

class ProviderStatusDto {
  const ProviderStatusDto({
    required this.provider,
    required this.authenticated,
  });

  final String provider;
  final bool authenticated;

  factory ProviderStatusDto.fromJson(Map<String, dynamic> json) {
    return ProviderStatusDto(
      provider: requireNonEmptyString(json, 'provider'),
      authenticated: requireBool(json, 'authenticated'),
    );
  }
}
