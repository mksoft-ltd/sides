import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/copy.dart';
import '../../../../shared/widgets/sides_mark.dart';
import '../../../ads/presentation/ad_banner_slot.dart';
import '../../../search/presentation/search_view.dart';
import '../../../settings/presentation/screens/outlets_screen.dart';
import '../../../story/presentation/providers/story_view_controller.dart';
import '../../domain/digest.dart';
import '../providers/digest_controller.dart';
import '../widgets/digest_feed_view.dart';
import '../widgets/sides_browse_view.dart';

/// Which home tab is open. A provider, so the choice survives a story push
/// and a layout swap.
final NotifierProvider<HomeTabController, HomeTab> homeTabProvider =
    NotifierProvider<HomeTabController, HomeTab>(HomeTabController.new);

enum HomeTab { today, search, bySide, outlets }

class HomeTabController extends Notifier<HomeTab> {
  @override
  HomeTab build() => HomeTab.today;
  void set(HomeTab tab) => state = tab;
}

/// The phone home: a news-app shell with a bottom tab bar. Today is the
/// front page (lead story, top stories, the rest), By side browses the
/// day's coverage one side at a time, Outlets lists who Sides reads.
class DigestListScreen extends ConsumerWidget {
  const DigestListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool hasDigest = ref.watch(
      digestControllerProvider.select((DigestState s) => s.digest != null),
    );
    final HomeTab tab = ref.watch(homeTabProvider);
    final Widget body = switch (tab) {
      HomeTab.today => DigestFeedView(
          onOpenStory: (Story s) => context.push(Routes.story(s.id)),
        ),
      HomeTab.search => SearchView(
          onOpenStory: (Story s, String? handle) => context.push(
            handle == null ? Routes.story(s.id) : Routes.storyIn(handle, s.id),
          ),
        ),
      HomeTab.bySide => SidesBrowseView(
          onOpenStory: (Story s, PerspectiveAxis axis) =>
              context.push(Routes.story(s.id, axis: axis)),
        ),
      HomeTab.outlets => const OutletsBody(),
    };
    return Scaffold(
      appBar: AppBar(
        title: const SidesWordmark(),
        actions: <Widget>[
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      body: body,
      // Ads only once there is content, and only at the screen edge, between
      // the content and the tab bar.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasDigest) const AdBannerSlot(),
          NavigationBar(
            selectedIndex: tab.index,
            onDestinationSelected: (int i) =>
                ref.read(homeTabProvider.notifier).set(HomeTab.values[i]),
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.today_outlined),
                selectedIcon: Icon(Icons.today),
                label: Copy.tabToday,
              ),
              NavigationDestination(
                icon: Icon(Icons.search),
                selectedIcon: Icon(Icons.search),
                label: Copy.tabSearch,
              ),
              NavigationDestination(
                icon: Icon(Icons.view_agenda_outlined),
                selectedIcon: Icon(Icons.view_agenda),
                label: Copy.tabBySide,
              ),
              NavigationDestination(
                icon: Icon(Icons.newspaper_outlined),
                selectedIcon: Icon(Icons.newspaper),
                label: Copy.tabOutlets,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
