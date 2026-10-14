import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import '../core/theme/app_theme.dart';
import '../features/digest/presentation/providers/digest_controller.dart';
import '../features/purchases/presentation/ad_free_controller.dart';
import '../features/settings/presentation/providers/settings_controller.dart';
import 'router.dart';

class SidesApp extends ConsumerStatefulWidget {
  const SidesApp({super.key, this.initialLocation = Routes.home});

  final String initialLocation;

  @override
  ConsumerState<SidesApp> createState() => _SidesAppState();
}

class _SidesAppState extends ConsumerState<SidesApp> {
  late final GoRouter _router =
      buildRouter(initialLocation: widget.initialLocation);
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Start the purchase listener at launch: a purchase that completed while
    // the app was closed is delivered in the first frames.
    ref.read(adFreeControllerProvider);
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ref.read(digestControllerProvider.notifier).onResumed();
        ref.read(adFreeControllerProvider.notifier).onResumed();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '${AppConfig.appName}: ${AppConfig.appTagline}',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: _router,
      // Honour the system text size up to 200%; layouts reflow to fit.
      builder: (BuildContext context, Widget? child) =>
          MediaQuery.withClampedTextScaling(
        maxScaleFactor: 2.0,
        child: child!,
      ),
    );
  }
}
