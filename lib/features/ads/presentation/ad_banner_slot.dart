import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../purchases/presentation/ad_free_controller.dart';
import '../data/ads_service.dart';

/// The only place a banner may appear: the bottom edge of a screen, outside
/// the sourced content. Disappears the instant the ad-free unlock lands.
class AdBannerSlot extends ConsumerWidget {
  const AdBannerSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(adFreeOwnedProvider)) return const SizedBox.shrink();
    return Center(
      heightFactor: 1,
      child: ref.watch(adsServiceProvider).banner(),
    );
  }
}
