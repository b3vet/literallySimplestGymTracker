import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/settings/settings_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/workout/application/rest_timer_controller.dart';
import 'features/workout/application/watch_sync_controller.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On return-to-foreground, re-validate the rest timer against the wall
    // clock (SOW-03 decision #5). A long background can suspend the in-memory
    // expiry timer; this reschedules it and clears a rest that expired while
    // we were away. Cold relaunch is handled in RestTimerController.build().
    if (state == AppLifecycleState.resumed) {
      ref.read(restTimerProvider.notifier).rehydrate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final settings = ref.watch(settingsProvider);
    final accent = lsAccentSpec(settings.accent);

    // Bring the watch sync layer to life at startup (lazy singleton; activates
    // WCSession, registers the native->Dart callbacks, and wires the
    // snapshot-push listeners). Provider never notifies, so watching it never
    // rebuilds App.
    ref.watch(watchBridgeControllerProvider);

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
        // Lock the system text-size accessibility scaler to 1.0x. The app
        // already uses a heavyweight bespoke type scale (LsType.displayXL
        // hits 62pt on the active workout screen); a user with iOS Settings
        // → Display & Brightness → Text Size set below default would
        // otherwise see the entire UI shrink — that's exactly what produced
        // the "iPhone 17 Pro Max renders much smaller than the simulator"
        // report (simulators default to 1.0x; a personal device often
        // doesn't). The simulator and the device now render identically.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.noScaling),
          child: LsTheme(
            surface: surface,
            accent: accent,
            brightness: brightness,
            child: child!,
          ),
        );
      },
    );
  }
}
