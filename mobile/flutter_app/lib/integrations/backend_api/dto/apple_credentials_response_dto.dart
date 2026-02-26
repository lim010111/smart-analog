class AppleCredentialsResponseDto {
  const AppleCredentialsResponseDto({
    required this.provider,
    required this.authenticated,
  });

  final String provider;
  final bool authenticated;

  factory AppleCredentialsResponseDto.fromJson(Map<String, dynamic> json) {
    return AppleCredentialsResponseDto(
      provider: json['provider'] as String? ?? 'apple',
      authenticated: json['authenticated'] as bool? ?? false,
    );
  }
}
