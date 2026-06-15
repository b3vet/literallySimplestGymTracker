import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/layout.dart';
import '../../programs/application/programs_provider.dart';
import '../data/program_templates.dart';
import '../data/template_seeder.dart';
import 'build_finale.dart';
import 'onboarding_fx.dart';
import 'steps/accent_step.dart';
import 'steps/log_set_step.dart';
import 'steps/loop_step.dart';
import 'steps/template_step.dart';
import 'steps/unit_step.dart';
import 'steps/welcome_step.dart';
import 'widgets/plate_progress_bar.dart';

const _kStepCount = 6;
const _kUnitStep = 3;

/// The first-run onboarding wizard. Six steps inside a persistent chrome
/// (plate progress + back/skip + a single forward CTA), ending with the chosen
/// template assembling itself and handing the user into the program editor.
///
/// Gating lives in `app_router.dart`: this is shown whenever
/// `settings.onboardingComplete == false`. The unit is held in local state and
/// only written at the finale (alongside the completion flag), so an
/// interrupted wizard always re-enters cleanly with no half-set state.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  WeightUnit _unit = WeightUnit.kg;
  ProgramTemplate? _selectedTemplate;

  bool _building = false;
  String? _buildError;

  static const _ctaLabels = [
    "LET'S GO",
    'GOT IT',
    'GOT IT',
    'CONTINUE',
    'THIS IS ME',
    'BUILD MY PROGRAM',
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  bool get _canAdvance =>
      _index != _kStepCount - 1 || _selectedTemplate != null;

  void _goto(int target, {bool jump = false}) {
    if (target < 0 || target >= _kStepCount || target == _index) return;
    setState(() => _index = target);
    if (jump || reduceMotionOf(context)) {
      _pages.jumpToPage(target);
    } else {
      _pages.animateToPage(
        target,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _next() {
    HapticFeedback.lightImpact(); // "another plate loaded"
    _goto(_index + 1);
  }

  void _back() => _goto(_index - 1);

  void _skip() => _goto(_kUnitStep, jump: true);

  void _onPrimary() {
    if (_index == _kStepCount - 1) {
      _startBuild();
    } else {
      _next();
    }
  }

  Future<void> _startBuild() async {
    final tpl = _selectedTemplate;
    if (tpl == null) return;
    final rm = reduceMotionOf(context);
    // Capture the router now — once we navigate, this screen's context is
    // defunct and can't be used for the follow-up push.
    final router = GoRouter.of(context);
    setState(() {
      _building = true;
      _buildError = null;
    });
    // Hold the finale on screen for its full assembly animation (kept in sync
    // with BuildFinale's controller), but commit the gate the instant the
    // (fast) seed resolves so a kill mid-animation is safe.
    final minShow = Future<void>.delayed(
        Duration(milliseconds: rm ? 1200 : 4500));
    try {
      final program = await ref.read(templateSeederProvider).seed(tpl);
      await ref.read(settingsProvider.notifier).setUnit(_unit);
      await ref.read(settingsProvider.notifier).setOnboardingComplete(true);
      await minShow;
      if (!mounted) return;
      ref.read(justOnboardedProgramIdProvider.notifier).set(program.id);
      // Land in the editor, but with Home seeded beneath it — a bare
      // `go('/programs/:id')` replaces the whole stack, leaving the editor
      // with nowhere to pop back to. go('/') then push() makes Back work.
      router.go('/');
      router.push('/programs/${program.id}');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _building = false;
        _buildError = "Couldn't build that program. Try again?";
      });
    }
  }

  Widget _buildStep(int i) {
    final active = _index == i;
    switch (i) {
      case 0:
        return WelcomeStep(isActive: active);
      case 1:
        return LoopStep(isActive: active);
      case 2:
        return LogSetStep(isActive: active);
      case 3:
        return UnitStep(
          isActive: active,
          unit: _unit,
          onChanged: (u) => setState(() => _unit = u),
        );
      case 4:
        return AccentStep(
          isActive: active,
          accent: ref.watch(settingsProvider).accent,
          onSelect: (a) =>
              ref.read(settingsProvider.notifier).setAccent(a),
        );
      default:
        return TemplateStep(
          isActive: active,
          selectedId: _selectedTemplate?.id,
          onSelect: (t) => setState(() => _selectedTemplate = t),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final showSkip = _index <= 2;
    return Scaffold(
      backgroundColor: t.surface.bg,
      body: SafeArea(
        child: Stack(
          children: [
            const WizardGridBackdrop(),
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      LsSpace.screen, 6, LsSpace.screen, 0),
                  child: _TopChrome(
                    step: _index + 1,
                    total: _kStepCount,
                    showBack: _index > 0,
                    showSkip: showSkip,
                    onBack: _back,
                    onSkip: _skip,
                  ),
                ),
                const SizedBox(height: LsGap.section),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _kStepCount,
                    itemBuilder: (context, i) => _buildStep(i),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      LsSpace.screen, 8, LsSpace.screen, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_buildError != null) ...[
                        Text(
                          _buildError!,
                          textAlign: TextAlign.center,
                          style: LsType.bodyM
                              .copyWith(color: LsSignals.danger),
                        ),
                        const SizedBox(height: LsGap.sub),
                      ],
                      LsButton(
                        label: _buildError != null && _index == _kStepCount - 1
                            ? 'RETRY BUILD'
                            : _ctaLabels[_index],
                        trailingIcon: Icons.arrow_forward,
                        expand: true,
                        minHeight: LsBox.cta,
                        onPressed: _canAdvance ? _onPrimary : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_building && _selectedTemplate != null)
              Positioned.fill(
                child: BuildFinale(template: _selectedTemplate!),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopChrome extends StatelessWidget {
  const _TopChrome({
    required this.step,
    required this.total,
    required this.showBack,
    required this.showSkip,
    required this.onBack,
    required this.onSkip,
  });
  final int step;
  final int total;
  final bool showBack;
  final bool showSkip;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showBack)
          LsIconSquare(
            icon: Icons.chevron_left,
            onTap: onBack,
            semanticLabel: 'Back',
          )
        else
          const SizedBox(width: LsBox.topbarIcon, height: LsBox.topbarIcon),
        const Spacer(),
        if (showSkip) ...[
          InkWell(
            borderRadius: BorderRadius.circular(LsRadius.r2),
            onTap: onSkip,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(
                'SKIP',
                style: LsType.monoMeta.copyWith(color: t.surface.text2),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        PlateProgressBar(step: step, total: total),
      ],
    );
  }
}
