import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/settings/settings_repository.dart';
import 'package:ls_workout_tracker/core/theme/app_theme.dart';
import 'package:ls_workout_tracker/features/onboarding/presentation/steps/accent_step.dart';
import 'package:ls_workout_tracker/features/onboarding/presentation/steps/log_set_step.dart';
import 'package:ls_workout_tracker/features/onboarding/presentation/steps/loop_step.dart';
import 'package:ls_workout_tracker/features/onboarding/presentation/steps/template_step.dart';
import 'package:ls_workout_tracker/features/onboarding/presentation/steps/unit_step.dart';
import 'package:ls_workout_tracker/features/onboarding/presentation/steps/welcome_step.dart';

const _redSpec = LsAccentSpec(
  id: LsAccent.red,
  label: 'Red',
  accent: Color(0xFFFF4D2E),
  accentHi: Color(0xFFFF7A5F),
  accentInk: Color(0xFFFFFFFF),
  accentDimSolidLight: Color(0xFFFFE5DF),
);

// Load the bundled families so the condensed display type lays out at its real
// (narrow) width — the default fallback is much wider and would wrap the 76pt
// headlines, producing false overflow failures the real app never sees.
Future<void> _loadFonts() async {
  const families = {
    'Antonio': ['Antonio-Regular.ttf', 'Antonio-SemiBold.ttf', 'Antonio-Bold.ttf'],
    'IBMPlexSans': ['IBMPlexSans-Regular.ttf', 'IBMPlexSans-Medium.ttf'],
    'JetBrainsMono': ['JetBrainsMono-Regular.ttf', 'JetBrainsMono-Medium.ttf', 'JetBrainsMono-SemiBold.ttf'],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final f in entry.value) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }
}

// Each step under reduce-motion (ambient loops off so the binding can settle),
// with an LsTheme ancestor and a bounded Scaffold body — a faithful phone frame.
Widget _wrap(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: LsTheme(
          surface: lsDark,
          accent: _redSpec,
          brightness: Brightness.dark,
          // ~580pt is what the host actually gives a step on a modern iPhone
          // (screen minus chrome, CTA and safe areas) — constrain to it so the
          // test catches real overflow, not just full-screen overflow.
          child: Scaffold(
            backgroundColor: lsDark.bg,
            body: Center(
              child: SizedBox(width: 393, height: 580, child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpStep(WidgetTester tester, Widget step) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_wrap(step));
  await tester.pump(const Duration(milliseconds: 950)); // entrance one-shot
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink()); // dispose
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  const t = Timeout(Duration(seconds: 20));

  testWidgets('WelcomeStep renders within a phone frame', timeout: t,
      (tester) async {
    await _pumpStep(tester, const WelcomeStep(isActive: true));
  });

  testWidgets('LoopStep renders within a phone frame', timeout: t,
      (tester) async {
    await _pumpStep(tester, const LoopStep(isActive: true));
  });

  testWidgets('LogSetStep renders within a phone frame', timeout: t,
      (tester) async {
    await _pumpStep(tester, const LogSetStep(isActive: true));
  });

  testWidgets('UnitStep renders within a phone frame', timeout: t,
      (tester) async {
    await _pumpStep(
      tester,
      UnitStep(isActive: true, unit: WeightUnit.kg, onChanged: (_) {}),
    );
  });

  testWidgets('AccentStep renders within a phone frame', timeout: t,
      (tester) async {
    await _pumpStep(
      tester,
      AccentStep(isActive: true, accent: LsAccent.red, onSelect: (_) {}),
    );
  });

  testWidgets('TemplateStep renders within a phone frame', timeout: t,
      (tester) async {
    await _pumpStep(
      tester,
      TemplateStep(isActive: true, selectedId: null, onSelect: (_) {}),
    );
  });

  testWidgets('TemplateStep shows selected state', timeout: t, (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(
      TemplateStep(
        isActive: true,
        selectedId: 'push_pull',
        onSelect: (_) {},
      ),
    ));
    await tester.pump(const Duration(milliseconds: 950));
    expect(find.text('PUSH PULL LEGS'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
