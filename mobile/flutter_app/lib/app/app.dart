import 'package:flutter/material.dart';

import '../core/localization/app_i18n.dart';
import '../features/calendar/presentation/mobile_home_screen.dart';

class ClockWidgetApp extends StatelessWidget {
  const ClockWidgetApp({
    super.key,
    required this.languageController,
    required this.startInScreenSaverMode,
  });

  final AppLanguageController languageController;
  final bool startInScreenSaverMode;

  @override
  Widget build(BuildContext context) {
    const darkBg = Color(0xFF0B0F19);
    const lightBg = Color(0xFFF8FAFC);

    return AppLanguageScope(
      controller: languageController,
      child: AnimatedBuilder(
        animation: languageController,
        builder: (context, _) {
          final i18n = context.i18n;
          return MaterialApp(
            title: i18n.appTitle,
            themeMode: ThemeMode.system,
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.light,
              scaffoldBackgroundColor: lightBg,
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF2563EB),
                secondary: Color(0xFF1D4ED8),
                surface: Color(0xCCFFFFFF),
                onSurface: Color(0xFF0F172A),
                outlineVariant: Color(0x3394A3B8),
              ),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              scaffoldBackgroundColor: darkBg,
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFF3B82F6),
                secondary: Color(0xFF2563EB),
                surface: Color(0xA00D111C),
                onSurface: Color(0xFFF4F7FF),
                outlineVariant: Color(0x268FA6D6),
              ),
            ),
            home: MobileHomeScreen(
              startInScreenSaverMode: startInScreenSaverMode,
            ),
          );
        },
      ),
    );
  }
}
