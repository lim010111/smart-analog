import 'package:flutter/services.dart';

class WidgetHostBridge {
  WidgetHostBridge();

  static const MethodChannel _channel = MethodChannel(
    'com.smartanalog.flutter_app/widget_host',
  );

  Future<void> syncWidgetReadPayload(Map<String, dynamic> payload) async {
    try {
      await _channel.invokeMethod<bool>('syncWidgetReadPayload', payload);
    } on PlatformException {
      // Keep app flows resilient when host-side widget bridge is unavailable.
    } on MissingPluginException {
      // Ignore in environments where native host integration is not loaded.
    }
  }

  Future<void> refreshHomeWidgets() async {
    try {
      await _channel.invokeMethod<bool>('refreshHomeWidgets');
    } on PlatformException {
      // Keep app flows resilient when host-side widget bridge is unavailable.
    } on MissingPluginException {
      // Ignore in environments where native host integration is not loaded.
    }
  }
}
