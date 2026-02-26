import 'package:flutter/material.dart';

import '../features/calendar/presentation/mobile_home_screen.dart';

class ClockWidgetApp extends StatelessWidget {
  const ClockWidgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Analog Mobile',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF355C7D)),
        useMaterial3: true,
      ),
      home: const MobileHomeScreen(),
    );
  }
}
