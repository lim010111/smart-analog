import 'json_contract.dart';

class GoogleAuthUrlResponseDto {
  const GoogleAuthUrlResponseDto({
    required this.provider,
    required this.authUrl,
    required this.state,
    required this.redirectUri,
    required this.clientId,
  });

  final String provider;
  final String authUrl;
  final String state;
  final String redirectUri;
  final String clientId;

  factory GoogleAuthUrlResponseDto.fromJson(Map<String, dynamic> json) {
    return GoogleAuthUrlResponseDto(
      provider: requireNonEmptyString(json, 'provider'),
      authUrl: requireNonEmptyString(json, 'auth_url'),
      state: requireNonEmptyString(json, 'state'),
      redirectUri: requireNonEmptyString(json, 'redirect_uri'),
      clientId: requireNonEmptyString(json, 'client_id'),
    );
  }
}
