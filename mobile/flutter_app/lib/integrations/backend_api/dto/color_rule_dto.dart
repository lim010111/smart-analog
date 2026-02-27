import 'json_contract.dart';

class ColorRuleDto {
  const ColorRuleDto({required this.colorHex, required this.label});

  final String colorHex;
  final String label;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'color_hex': colorHex, 'label': label};
  }

  factory ColorRuleDto.fromJson(Map<String, dynamic> json) {
    return ColorRuleDto(
      colorHex: requireNonEmptyString(json, 'color_hex'),
      label: requireNonEmptyString(json, 'label'),
    );
  }
}
