import 'json_contract.dart';

class ProvidersResponseDto {
  const ProvidersResponseDto({
    required this.defaultProvider,
    required this.providers,
  });

  final String defaultProvider;
  final List<String> providers;

  factory ProvidersResponseDto.fromJson(Map<String, dynamic> json) {
    return ProvidersResponseDto(
      defaultProvider: requireNonEmptyString(json, 'default_provider'),
      providers: requireStringList(json, 'providers'),
    );
  }
}
