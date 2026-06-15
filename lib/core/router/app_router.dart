import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/history/presentation/history_screen.dart';
import '../../features/history/presentation/session_detail_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/programs/presentation/day_editor_screen.dart';
import '../../features/programs/presentation/program_editor_screen.dart';
import '../../features/programs/presentation/programs_list_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/stats/presentation/stats_screen.dart';
import '../../features/tips/presentation/tips_screen.dart';
import '../../features/workout/presentation/active_workout_screen.dart';
import '../../features/workout/presentation/start_workout_screen.dart';
import '../../features/workout/presentation/summary_screen.dart';
import '../settings/settings_provider.dart';
import 'page_transitions.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final complete = ref.read(settingsProvider).onboardingComplete;
      final onboarding = state.matchedLocation == '/onboarding';
      if (!complete) {
        // First run (or an interrupted one): force the wizard.
        return onboarding ? null : '/onboarding';
      }
      // Onboarding done: never force the user *off* /onboarding here. The
      // wizard's finale navigates into the editor itself, and a redirect would
      // cut the build animation short. Normal launches start at '/' and fall
      // through to null anyway.
      return null;
    },
    refreshListenable: _RiverpodRefresh(ref),
    routes: [
      // Every route uses `pageBuilder` + `liftPage` so the whole app
      // shares a single navigation transition language (see
      // page_transitions.dart). Switching back to `builder:` on any
      // route reverts that route to the platform default — useful for
      // debugging, but otherwise keep them consistent.
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) =>
            liftPage(key: state.pageKey, child: const OnboardingScreen()),
      ),
      GoRoute(
        path: '/',
        pageBuilder: (context, state) =>
            liftPage(key: state.pageKey, child: const HomeScreen()),
      ),
      GoRoute(
        path: '/programs',
        pageBuilder: (context, state) =>
            liftPage(key: state.pageKey, child: const ProgramsListScreen()),
        routes: [
          GoRoute(
            path: ':pid',
            pageBuilder: (context, state) => liftPage(
              key: state.pageKey,
              child: ProgramEditorScreen(
                programId: state.pathParameters['pid']!,
              ),
            ),
            routes: [
              GoRoute(
                path: 'days/:did',
                pageBuilder: (context, state) => liftPage(
                  key: state.pageKey,
                  child: DayEditorScreen(
                    programId: state.pathParameters['pid']!,
                    dayId: state.pathParameters['did']!,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/workout/start',
        pageBuilder: (context, state) =>
            liftPage(key: state.pageKey, child: const StartWorkoutScreen()),
      ),
      GoRoute(
        path: '/workout/active',
        pageBuilder: (context, state) =>
            liftPage(key: state.pageKey, child: const ActiveWorkoutScreen()),
      ),
      GoRoute(
        path: '/workout/summary/:sid',
        pageBuilder: (context, state) => liftPage(
          key: state.pageKey,
          child: SummaryScreen(sessionId: state.pathParameters['sid']!),
        ),
      ),
      GoRoute(
        path: '/history',
        pageBuilder: (context, state) =>
            liftPage(key: state.pageKey, child: const HistoryScreen()),
        routes: [
          GoRoute(
            path: ':sid',
            pageBuilder: (context, state) => liftPage(
              key: state.pageKey,
              child: SessionDetailScreen(
                sessionId: state.pathParameters['sid']!,
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/stats',
        pageBuilder: (context, state) =>
            liftPage(key: state.pageKey, child: const StatsScreen()),
      ),
      GoRoute(
        path: '/tips',
        pageBuilder: (context, state) =>
            liftPage(key: state.pageKey, child: const TipsScreen()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) =>
            liftPage(key: state.pageKey, child: const SettingsScreen()),
      ),
    ],
  );
});

class _RiverpodRefresh extends ChangeNotifier {
  _RiverpodRefresh(Ref ref) {
    _sub = ref.listen(settingsProvider, (_, _) => notifyListeners());
  }
  late final ProviderSubscription _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
