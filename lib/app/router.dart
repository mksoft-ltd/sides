import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'adaptive_pages.dart';

import '../core/layout/breakpoints.dart';
import '../features/settings/presentation/screens/outlets_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/story/presentation/widgets/story_detail_view.dart';

abstract final class Routes {
  static const String home = '/';
  static const String settings = '/settings';
  static const String outlets = '/settings/outlets';
  /// `?axis=bloc` opens the West / East view directly.
  static String story(
    String id, {
    PerspectiveAxis axis = PerspectiveAxis.lean,
  }) =>
      axis == PerspectiveAxis.bloc ? '/story/$id?axis=bloc' : '/story/$id';
}

/// A fresh router per app instance (tests build their own app each time).
/// Adaptive routes (phase 5): `/` and `/story/:id` each render a phone page
/// or the tablet master-detail layout (see `adaptive_pages.dart`). Phones keep
/// the phase 4 behaviour: a MaterialPage per story, pushed over the list. At
/// tablet widths selecting a story is a `context.go`: go_router keys a
/// declarative match by its route pattern (`/story/:id`), not its location,
/// so going from one story to another updates the same NoTransitionPage in
/// place (no push, no animation) while the URL still reads `/story/:id`.
GoRouter buildRouter({String initialLocation = Routes.home}) => GoRouter(
      initialLocation: initialLocation,
      routes: <RouteBase>[
        GoRoute(
          path: Routes.home,
          builder: (BuildContext context, GoRouterState state) =>
              const HomePage(),
          routes: <RouteBase>[
            GoRoute(
              path: 'story/:id',
              pageBuilder: (BuildContext context, GoRouterState state) {
                final Widget child = StoryPage(
                  storyId: state.pathParameters['id']!,
                  initialAxis: state.uri.queryParameters['axis'] == 'bloc'
                      ? PerspectiveAxis.bloc
                      : PerspectiveAxis.lean,
                );
                if (LayoutSize.of(context) == LayoutSize.compact) {
                  // What go_router builds for a plain `builder` route.
                  return MaterialPage<void>(
                    key: state.pageKey,
                    name: state.name,
                    arguments: <String, String>{
                      ...state.pathParameters,
                      ...state.uri.queryParameters,
                    },
                    restorationId: state.pageKey.value,
                    child: child,
                  );
                }
                return NoTransitionPage<void>(key: state.pageKey, child: child);
              },
            ),
            GoRoute(
              path: 'settings',
              builder: (BuildContext context, GoRouterState state) =>
                  const SettingsScreen(),
              routes: <RouteBase>[
                GoRoute(
                  path: 'outlets',
                  builder: (BuildContext context, GoRouterState state) =>
                      const OutletsScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    );
