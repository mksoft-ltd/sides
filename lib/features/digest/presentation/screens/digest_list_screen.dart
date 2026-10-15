import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../shared/widgets/sides_mark.dart';
import '../../../ads/presentation/ad_banner_slot.dart';
import '../../domain/digest.dart';
import '../providers/digest_controller.dart';
import '../widgets/digest_list_view.dart';

class DigestListScreen extends ConsumerWidget {
  const DigestListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool hasDigest = ref.watch(
      digestControllerProvider.select((DigestState s) => s.digest != null),
    );
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
      body: DigestListView(
        onOpenStory: (Story s) => context.push(Routes.story(s.id)),
      ),
      // Ads only once there is content, and only at the screen edge.
      bottomNavigationBar: hasDigest ? const AdBannerSlot() : null,
    );
  }
}
