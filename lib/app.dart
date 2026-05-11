import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/settings/settings_provider.dart';
import 'core/theme/app_theme.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final settings = ref.watch(settingsProvider);
    final accent = lsAccentSpec(settings.accent);

    final lightTheme = LsTheme.buildThemeData(
      s: lsLight,
      a: accent,
      brightness: Brightness.light,
    );
    final darkTheme = LsTheme.buildThemeData(
      s: lsDark,
      a: accent,
      brightness: Brightness.dark,
    );

    return MaterialApp.router(
      title: 'LS Gym Track',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: settings.themeMode,
      routerConfig: router,
      builder: (context, child) {
        // Pick surface tokens from the resolved theme brightness — this auto-
        // adapts when themeMode is `system`. We compute it from the platform
        // dispatcher's platformBrightness when the user picked `system`.
        final platformBrightness = MediaQuery.platformBrightnessOf(context);
        final brightness = switch (settings.themeMode) {
          ThemeMode.light => Brightness.light,
          ThemeMode.dark => Brightness.dark,
          ThemeMode.system => platformBrightness,
        };
        final surface = brightness == Brightness.dark ? lsDark : lsLight;
        return LsTheme(
          surface: surface,
          accent: accent,
          brightness: brightness,
          child: child!,
        );
      },
    );
  }
}
