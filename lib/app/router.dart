import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/digest/presentation/screens/digest_list_screen.dart';
import '../features/settings/presentation/screens/outlets_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/story/presentation/screens/story_detail_screen.dart';
import '../features/story/presentation/widgets/story_detail_view.dart';

abstract final class Routes {
  static const String home = '/';
  static const String settings = '/settings';
  static const String outlets = '/settings/outlets';
  /// `?axis=bloc` opens the West / East view directly.
  static String story(String id) => '/story/$id';
}

/// A fresh router per app instance (tests build their own app each time).
/// Phase 5: at medium/expanded widths the home route renders master-detail
/// and `/story/:id` selects inside it instead of pushing a page.
GoRouter buildRouter({String initialLocation = Routes.home}) => GoRouter(
      initialLocation: initialLocation,
      routes: <RouteBase>[
        GoRoute(
          path: Routes.home,
          builder: (BuildContext context, GoRouterState state) =>
              const DigestListScreen(),
          routes: <RouteBase>[
            GoRoute(
              path: 'story/:id',
              builder: (BuildContext context, GoRouterState state) =>
                  StoryDetailScreen(
                storyId: state.pathParameters['id']!,
                initialAxis: state.uri.queryParameters['axis'] == 'bloc'
                    ? PerspectiveAxis.bloc
                    : PerspectiveAxis.lean,
              ),
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
