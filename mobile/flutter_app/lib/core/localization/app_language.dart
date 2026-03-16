enum AppLanguage { english, korean }

extension AppLanguageX on AppLanguage {
  String get code {
    switch (this) {
      case AppLanguage.english:
        return 'en';
      case AppLanguage.korean:
        return 'ko';
    }
  }

  static AppLanguage fromCode(String? code) {
    final normalized = (code ?? '').trim().toLowerCase();
    if (normalized == 'ko' || normalized == 'kr' || normalized == 'korean') {
      return AppLanguage.korean;
    }
    return AppLanguage.english;
  }
}
