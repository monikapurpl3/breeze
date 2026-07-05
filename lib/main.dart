import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'src/app_controller.dart';
import 'src/app_scope.dart';
import 'src/home_widget_service.dart';
import 'src/screens/home_screen.dart';
import 'src/screens/onboarding_screen.dart';
import 'src/screens/pairing_screen.dart';
import 'src/secure_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Register the home-screen widget's interactive background callback so its
  // buttons can control units without opening the app. Best-effort.
  HomeWidgetService.init();
  final controller = AppController(SecureStore());
  controller.init();
  runApp(BreezeApp(controller: controller));
}

class BreezeApp extends StatelessWidget {
  final AppController controller;
  const BreezeApp({super.key, required this.controller});

  static const _fallbackSeed = Color(0xFF4FD1C5); // teal, matches the web UI

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final light = lightDynamic ??
            ColorScheme.fromSeed(seedColor: _fallbackSeed, brightness: Brightness.light);
        final dark = darkDynamic ??
            ColorScheme.fromSeed(seedColor: _fallbackSeed, brightness: Brightness.dark);
        return AppScope(
          controller: controller,
          child: MaterialApp(
            title: 'Breeze',
            debugShowCheckedModeBanner: false,
            themeMode: ThemeMode.system, // dynamic dark/light per system
            theme: ThemeData(colorScheme: light, useMaterial3: true),
            darkTheme: ThemeData(colorScheme: dark, useMaterial3: true),
            home: const _Gate(),
          ),
        );
      },
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        switch (c.stage) {
          case AppStage.onboarding:
            return const OnboardingScreen();
          case AppStage.pairing:
            return const PairingScreen();
          case AppStage.home:
            return const HomeScreen();
          case AppStage.loading:
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
      },
    );
  }
}
