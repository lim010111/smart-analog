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
      provider: json['provider'] as String? ?? 'google',
      authUrl: json['auth_url'] as String? ?? '',
      state: json['state'] as String? ?? '',
      redirectUri: json['redirect_uri'] as String? ?? '',
      clientId: json['client_id'] as String? ?? '',
    );
  }
}
