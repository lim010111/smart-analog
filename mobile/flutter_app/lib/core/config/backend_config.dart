class BackendConfig {
  const BackendConfig._();

  static const String googleMobileCallbackUri = 'smartanalog://auth/google';
  static const String _defaultRemoteBaseUrl =
      'https://smart-analog-clock.fly.dev';

  static String resolveBaseUrl() {
    const fromDefine = String.fromEnvironment('BACKEND_BASE_URL');
    if (fromDefine.isNotEmpty) {
      return fromDefine;
    }

    return _defaultRemoteBaseUrl;
  }
}
