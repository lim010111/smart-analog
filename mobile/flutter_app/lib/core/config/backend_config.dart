import 'dart:io';

class BackendConfig {
  const BackendConfig._();

  static const String googleMobileCallbackUri = 'smartanalog://auth/google';

  static String resolveBaseUrl() {
    const fromDefine = String.fromEnvironment('BACKEND_BASE_URL');
    if (fromDefine.isNotEmpty) {
      return fromDefine;
    }

    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8000';
    }

    return 'http://127.0.0.1:8000';
  }
}
