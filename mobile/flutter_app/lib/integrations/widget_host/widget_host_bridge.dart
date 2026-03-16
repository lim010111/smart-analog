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

  Future<void> enableScreenSaverMode() async {
    try {
      await _channel.invokeMethod<bool>('enableScreenSaverMode');
    } on PlatformException {
      // Keep app flows resilient when host-side screen mode bridge is unavailable.
    } on MissingPluginException {
      // Ignore in environments where native host integration is not loaded.
    }
  }

  Future<void> disableScreenSaverMode() async {
    try {
      await _channel.invokeMethod<bool>('disableScreenSaverMode');
    } on PlatformException {
      // Keep app flows resilient when host-side screen mode bridge is unavailable.
    } on MissingPluginException {
      // Ignore in environments where native host integration is not loaded.
    }
  }

  Future<bool> enableAutoLockScreenMode() async {
    try {
      await _channel.invokeMethod<bool>('enableAutoLockScreenMode');
      return true;
    } on PlatformException {
      // Keep app flows resilient when host-side auto-launch bridge is unavailable.
      return false;
    } on MissingPluginException {
      // Ignore in environments where native host integration is not loaded.
      return false;
    }
  }

  Future<bool> disableAutoLockScreenMode() async {
    try {
      await _channel.invokeMethod<bool>('disableAutoLockScreenMode');
      return true;
    } on PlatformException {
      // Keep app flows resilient when host-side auto-launch bridge is unavailable.
      return false;
    } on MissingPluginException {
      // Ignore in environments where native host integration is not loaded.
      return false;
    }
  }

  Future<bool> checkNotificationPermission() async {
    try {
      return await _channel.invokeMethod<bool>('checkNotificationPermission') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> requestNotificationPermission() async {
    try {
      return await _channel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> isNotificationPermissionRuntimeRequired() async {
    try {
      return await _channel.invokeMethod<bool>(
            'isNotificationPermissionRuntimeRequired',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await _channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> openBatteryOptimizationSettings() async {
    try {
      return await _channel.invokeMethod<bool>(
            'openBatteryOptimizationSettings',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> openNotificationSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openNotificationSettings') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> openAppPermissionSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAppPermissionSettings') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> canDrawOverlays() async {
    try {
      return await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> openOverlayPermissionSettings() async {
    try {
      return await _channel.invokeMethod<bool>(
            'openOverlayPermissionSettings',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> canUseFullScreenIntent() async {
    try {
      return await _channel.invokeMethod<bool>('canUseFullScreenIntent') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> openFullScreenIntentSettings() async {
    try {
      return await _channel.invokeMethod<bool>(
            'openFullScreenIntentSettings',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<String?> consumeLaunchAction() async {
    try {
      return await _channel.invokeMethod<String>('consumeLaunchAction');
    } on PlatformException {
      // Keep app flows resilient when host-side launch bridge is unavailable.
      return null;
    } on MissingPluginException {
      // Ignore in environments where native host integration is not loaded.
      return null;
    }
  }
}
