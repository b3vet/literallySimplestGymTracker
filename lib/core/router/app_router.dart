import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/history/presentation/history_screen.dart';
import '../../features/history/presentation/session_detail_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/presentation/unit_pick_screen.dart';
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

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final unit = ref.read(settingsProvider).unit;
      final onboarding = state.matchedLocation == '/onboarding/unit';
      if (unit == null && !onboarding) return '/onboarding/unit';
      if (unit != null && onboarding) return '/';
      return null;
    },
    refreshListenable: _RiverpodRefresh(ref),
    routes: [
      GoRoute(
        path: '/onboarding/unit',
        builder: (context, state) => const UnitPickScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/programs',
        builder: (context, state) => const ProgramsListScreen(),
        routes: [
          GoRoute(
            path: ':pid',
            builder: (context, state) => ProgramEditorScreen(
              programId: state.pathParameters['pid']!,
            ),
            routes: [
              GoRoute(
                path: 'days/:did',
                builder: (context, state) => DayEditorScreen(
                  programId: state.pathParameters['pid']!,
                  dayId: state.pathParameters['did']!,
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/workout/start',
        builder: (context, state) => const StartWorkoutScreen(),
      ),
      GoRoute(
        path: '/workout/active',
        builder: (context, state) => const ActiveWorkoutScreen(),
      ),
      GoRoute(
        path: '/workout/summary/:sid',
        builder: (context, state) =>
            SummaryScreen(sessionId: state.pathParameters['sid']!),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
        routes: [
          GoRoute(
            path: ':sid',
            builder: (context, state) => SessionDetailScreen(
              sessionId: state.pathParameters['sid']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/stats',
        builder: (context, state) => const StatsScreen(),
      ),
      GoRoute(
        path: '/tips',
        builder: (context, state) => const TipsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
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
