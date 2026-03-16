import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/localization/app_i18n.dart';
import 'integrations/widget_host/widget_host_bridge.dart';

const String _lockScreenAutoModeEnabledKey = 'lock_screen_auto_mode_enabled_v1';
const String _hostLaunchActionOpenScreenSaver = 'open_screen_saver';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final languageController = await AppLanguageController.load();
  final prefs = await SharedPreferences.getInstance();
  final lockScreenAutoModeEnabled =
      prefs.getBool(_lockScreenAutoModeEnabledKey) ?? false;
  final initialHostLaunchAction = await WidgetHostBridge()
      .consumeLaunchAction();
  final startInScreenSaverMode =
      lockScreenAutoModeEnabled &&
      initialHostLaunchAction == _hostLaunchActionOpenScreenSaver;

  runApp(
    ClockWidgetApp(
      languageController: languageController,
      startInScreenSaverMode: startInScreenSaverMode,
    ),
  );
}
