import 'json_contract.dart';

class ProviderAuthResponseDto {
  const ProviderAuthResponseDto({
    required this.provider,
    required this.authenticated,
  });

  final String provider;
  final bool authenticated;

  factory ProviderAuthResponseDto.fromJson(Map<String, dynamic> json) {
    return ProviderAuthResponseDto(
      provider: requireNonEmptyString(json, 'provider'),
      authenticated: requireBool(json, 'authenticated'),
    );
  }
}

class ProviderLogoutResponseDto {
  const ProviderLogoutResponseDto({
    required this.provider,
    required this.loggedOut,
  });

  final String provider;
  final bool loggedOut;

  factory ProviderLogoutResponseDto.fromJson(Map<String, dynamic> json) {
    return ProviderLogoutResponseDto(
      provider: requireNonEmptyString(json, 'provider'),
      loggedOut: requireBool(json, 'logged_out'),
    );
  }
}
