class ProviderStatusDto {
  const ProviderStatusDto({
    required this.provider,
    required this.authenticated,
  });

  final String provider;
  final bool authenticated;

  factory ProviderStatusDto.fromJson(Map<String, dynamic> json) {
    return ProviderStatusDto(
      provider: json['provider'] as String? ?? 'unknown',
      authenticated: json['authenticated'] as bool? ?? false,
    );
  }
}
