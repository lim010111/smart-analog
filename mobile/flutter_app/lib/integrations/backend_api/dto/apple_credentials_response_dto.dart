import 'json_contract.dart';

class AppleCredentialsResponseDto {
  const AppleCredentialsResponseDto({
    required this.provider,
    required this.authenticated,
  });

  final String provider;
  final bool authenticated;

  factory AppleCredentialsResponseDto.fromJson(Map<String, dynamic> json) {
    return AppleCredentialsResponseDto(
      provider: requireNonEmptyString(json, 'provider'),
      authenticated: requireBool(json, 'authenticated'),
    );
  }
}
