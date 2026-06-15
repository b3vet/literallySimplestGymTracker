import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/spec.dart';
import '../../../../core/widgets/pickers/picker_column.dart';
import '../onboarding_fx.dart';

const _weights = <double>[50, 52.5, 55, 57.5, 60, 62.5, 65, 67.5, 70];
const _reps = <int>[6, 7, 8, 9, 10, 11, 12, 13, 14, 15];
const _wStart = 4; // 60
const _wTarget = 5; // 62.5
const _rStart = 6; // 12
const _rTarget = 4; // 10

String _fmtW(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Step 2 — teach the single highest-frequency gesture by handing the user a
/// real, flickable wheel. If they don't touch it, it demos itself (spin → save
/// pulse) every few seconds. The instant they touch it, it's theirs.
class LogSetStep extends StatefulWidget {
  const LogSetStep({super.key, required this.isActive});
  final bool isActive;

  @override
  State<LogSetStep> createState() => _LogSetStepState();
}

class _LogSetStepState extends State<LogSetStep>
    with TickerProviderStateMixin, StepEntrance<LogSetStep> {
  @override
  bool get isActive => widget.isActive;

  final _weightCtl = FixedExtentScrollController(initialItem: _wStart);
  final _repsCtl = FixedExtentScrollController(initialItem: _rStart);
  late final AnimationController _save = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  Timer? _demoTimer;
  bool _userTouched = false;

  @override
  void didUpdateWidget(covariant LogSetStep old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) _scheduleDemo();
    if (!widget.isActive) _demoTimer?.cancel();
  }

  @override
  void initState() {
    super.initState();
    // Defer to post-frame: _scheduleDemo reads MediaQuery (reduce-motion),
    // which is illegal during initState.
    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isActive) _scheduleDemo();
      });
    }
  }

  void _scheduleDemo() {
    _demoTimer?.cancel();
    // No self-demo (and no lingering timer) under reduce-motion.
    if (reduceMotionOf(context)) return;
    _demoTimer = Timer(const Duration(milliseconds: 1600), _runDemo);
  }

  bool get _canDemo =>
      mounted &&
      widget.isActive &&
      !_userTouched &&
      !reduceMotionOf(context) &&
      !(MediaQuery.maybeOf(context)?.accessibleNavigation ?? false);

  Future<void> _runDemo() async {
    if (!_canDemo) return;
    await _weightCtl.animateToItem(_wTarget,
        duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    if (!_canDemo) return;
    await _repsCtl.animateToItem(_rTarget,
        duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
    if (!_canDemo) return;
    HapticFeedback.lightImpact();
    _save.forward(from: 0);
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (!_canDemo) return;
    // Reset and loop.
    await _weightCtl.animateToItem(_wStart,
        duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    if (!_canDemo) return;
    await _repsCtl.animateToItem(_rStart,
        duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
    _scheduleDemo();
  }

  void _onTouched() {
    if (_userTouched) return;
    setState(() => _userTouched = true);
    _demoTimer?.cancel();
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _weightCtl.dispose();
    _repsCtl.dispose();
    _save.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LsSpace.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Reveal(
                animation: entrance,
                start: 0.0,
                end: 0.24,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 16, height: 2, color: t.accent.accent),
                    const SizedBox(width: 10),
                    Text('LOG A SET',
                        style:
                            LsType.monoMeta.copyWith(color: t.surface.text2)),
                  ],
                ),
              ),
              const SizedBox(height: LsGap.sub),
              for (final (i, line) in const ['SPIN. SAVE.', "THAT'S IT."].indexed)
                Reveal(
                  animation: entrance,
                  start: 0.04 + i * 0.06,
                  end: 0.26 + i * 0.06,
                  child: Text(line, style: onbHeadline(t)),
                ),
              const SizedBox(height: LsGap.sub),
              Reveal(
                animation: entrance,
                start: 0.22,
                end: 0.42,
                child: SizedBox(
                  width: 270,
                  child: Text(
                    'Between sets, dial your weight and reps, then log it. '
                    'Try it →',
                    textAlign: TextAlign.right,
                    style: LsType.bodyS.copyWith(color: t.surface.text2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LsGap.loose),
          Reveal(
            animation: entrance,
            start: 0.20,
            end: 0.50,
            dy: 18,
            child: Listener(
              onPointerDown: (_) => _onTouched(),
              child: SizedBox(
                height: 168,
                child: Row(
                  children: [
                    Expanded(
                      child: PickerColumn(
                        label: 'Weight',
                        unitSuffix: 'kg',
                        controller: _weightCtl,
                        itemCount: _weights.length,
                        // Rebuild on every tick so the selected (centred) value
                        // gets the highlighted style and the others grey out —
                        // matching the real log sheet, which setStates here too.
                        onChanged: (_) => setState(() {}),
                        // accent:false → high-contrast surface.text for the
                        // selected value, matching the reps column (the accent
                        // variant greys out to text2 in light mode).
                        builder: (i, selected) => PickerText(_fmtW(_weights[i]),
                            selected: selected, accent: false),
                      ),
                    ),
                    const SizedBox(width: LsGap.section),
                    Expanded(
                      child: PickerColumn(
                        label: 'Reps',
                        controller: _repsCtl,
                        itemCount: _reps.length,
                        // Rebuild on every tick so the selected (centred) value
                        // gets the highlighted style and the others grey out —
                        // matching the real log sheet, which setStates here too.
                        onChanged: (_) => setState(() {}),
                        builder: (i, selected) => PickerText('${_reps[i]}',
                            selected: selected, accent: false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: LsGap.loose),
          Reveal(
            animation: entrance,
            start: 0.34,
            end: 0.56,
            child: _SaveDemoChip(flash: _save),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

/// A non-functional "SAVE SET" chip that demonstrates the save beat: it
/// depresses, flashes a check, and emits one accent ripple.
class _SaveDemoChip extends StatelessWidget {
  const _SaveDemoChip({required this.flash});
  final Animation<double> flash;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return AnimatedBuilder(
      animation: flash,
      builder: (context, _) {
        final v = flash.value;
        // Depress in the first 18%, release after.
        final press = v < 0.18 ? v / 0.18 : (1 - ((v - 0.18) / 0.82));
        final scale = 1 - 0.03 * press.clamp(0.0, 1.0);
        final ring = Curves.easeOut.transform(v);
        return Stack(
          alignment: Alignment.center,
          children: [
            if (v > 0 && v < 1)
              Container(
                height: LsBox.cta,
                width: double.infinity,
                margin: EdgeInsets.symmetric(horizontal: 40 * (1 - ring)),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(LsRadius.r3),
                  border: Border.all(
                    color: t.accent.accent.withValues(alpha: (1 - ring) * 0.6),
                    width: 2,
                  ),
                ),
              ),
            Transform.scale(
              scale: scale,
              child: Container(
                height: LsBox.cta,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.accent.accent,
                  borderRadius: BorderRadius.circular(LsRadius.r3),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'LOG SET',
                      style: LsType.button.copyWith(color: t.accent.accentInk),
                    ),
                    const SizedBox(width: 10),
                    Icon(Icons.check,
                        size: 20, color: t.accent.accentInk),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
