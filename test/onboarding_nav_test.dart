import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Mirrors the app's route shape (Home as a top-level peer of the nested
// /programs/:id editor) to prove the onboarding finale's "go('/') + push(...)"
// leaves a stack you can actually pop back through to Home — the exact bug the
// fix addresses (a bare go('/programs/:id') wipes Home and dead-ends).
void main() {
  testWidgets('finale go + push leaves a Home-rooted, poppable stack',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
            path: '/onboarding',
            builder: (_, _) => const Text('ONBOARDING')),
        GoRoute(path: '/', builder: (_, _) => const Text('HOME')),
        GoRoute(
          path: '/programs',
          builder: (_, _) => const Text('PROGRAMS'),
          routes: [
            GoRoute(path: ':id', builder: (_, _) => const Text('EDITOR')),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('ONBOARDING'), findsOneWidget);

    // What the finale does:
    router.go('/');
    router.push('/programs/abc123');
    await tester.pumpAndSettle();

    // Lands in the editor...
    expect(find.text('EDITOR'), findsOneWidget);
    // ...and can be popped (the reported bug was that it couldn't).
    expect(router.canPop(), isTrue);

    // Popping all the way must bottom out at HOME, never the wizard.
    var guard = 0;
    while (router.canPop() && guard++ < 5) {
      router.pop();
      await tester.pumpAndSettle();
    }
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('ONBOARDING'), findsNothing);
  });
}
