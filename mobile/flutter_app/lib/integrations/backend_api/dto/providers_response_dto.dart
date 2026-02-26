class ProvidersResponseDto {
  const ProvidersResponseDto({
    required this.defaultProvider,
    required this.providers,
  });

  final String defaultProvider;
  final List<String> providers;

  factory ProvidersResponseDto.fromJson(Map<String, dynamic> json) {
    final providersJson = json['providers'] as List<dynamic>? ?? <dynamic>[];
    return ProvidersResponseDto(
      defaultProvider: json['default_provider'] as String? ?? 'google',
      providers: providersJson.whereType<String>().toList(),
    );
  }
}
