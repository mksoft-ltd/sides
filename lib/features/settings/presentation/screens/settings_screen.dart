import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/constants/copy.dart';
import '../../../../core/launcher/link_launcher.dart';
import '../../../../shared/widgets/report_story_tile.dart';
import '../../../ads/data/ads_service.dart';
import '../../../purchases/presentation/ad_free_controller.dart';
import '../providers/settings_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static String noticeText(AdFreeNotice n) => switch (n) {
        AdFreeNotice.purchased => 'Ads removed. Thank you for supporting Sides.',
        AdFreeNotice.restored => 'Your ad-free purchase has been restored.',
        AdFreeNotice.nothingToRestore =>
          'No previous ad-free purchase was found for this account.',
        AdFreeNotice.cancelled => 'Purchase cancelled. You have not been charged.',
        AdFreeNotice.failed =>
          'The purchase didn\'t go through. You have not been charged.',
        AdFreeNotice.pending =>
          'Your purchase is waiting for approval. Ads will disappear once it '
              'completes.',
        AdFreeNotice.storeUnavailable =>
          'The store isn\'t available right now. Please try again later.',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AdFreeState>(adFreeControllerProvider,
        (AdFreeState? prev, AdFreeState next) {
      final AdFreeNotice? n = next.notice;
      if (n != null && next.noticeSerial != prev?.noticeSerial) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(noticeText(n))));
      }
    });

    final ThemeData theme = Theme.of(context);
    final ThemeMode mode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: <Widget>[
          const _Header('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<ThemeMode>>[
                ButtonSegment<ThemeMode>(
                    value: ThemeMode.system, label: Text('System')),
                ButtonSegment<ThemeMode>(
                    value: ThemeMode.light, label: Text('Light')),
                ButtonSegment<ThemeMode>(
                    value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: <ThemeMode>{mode},
              onSelectionChanged: (Set<ThemeMode> s) =>
                  ref.read(themeModeProvider.notifier).set(s.first),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.format_size),
            title: Text('Text size'),
            subtitle: Text(
              'Sides follows your device\'s text size setting, up to 200%.',
            ),
          ),
          const Divider(),
          const _Header('Ads'),
          const _AdFreeTile(),
          const _PrivacyOptionsTile(),
          const Divider(),
          const _Header('How it works'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(Copy.howItWorks, style: theme.textTheme.bodyMedium),
          ),
          const ReportStoryTile(),
          ListTile(
            leading: const Icon(Icons.newspaper_outlined),
            title: const Text('Outlets and ratings'),
            subtitle: const Text('Every outlet Sides reads, with its lean, '
                'region and ownership'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.outlets),
          ),
          const Divider(),
          const _Header('About'),
          const ListTile(
            leading: Icon(Icons.business_outlined),
            title: Text(Copy.publishedBy),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text(Copy.contact),
            subtitle: const Text(AppConfig.contactEmail),
            onTap: () async {
              final bool ok = await ref
                  .read(linkLauncherProvider)
                  .compose(AppConfig.contactMailto);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text(Copy.contactFailed)),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text(Copy.privacyPolicy),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => ref
                .read(linkLauncherProvider)
                .open(Uri.parse(AppConfig.privacyPolicyUrl)),
          ),
          const ListTile(
            title: Text('${AppConfig.appName}: ${AppConfig.appTagline}'),
            subtitle: Text(AppConfig.copyright),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Semantics(
          header: true,
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
      );
}

class _AdFreeTile extends ConsumerWidget {
  const _AdFreeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AdFreeState s = ref.watch(adFreeControllerProvider);
    final AdFreeController c = ref.read(adFreeControllerProvider.notifier);
    if (s.owned) {
      return const ListTile(
        leading: Icon(Icons.check_circle_outline),
        title: Text('Ad-free unlocked'),
        subtitle: Text('Thank you for supporting Sides.'),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'A one-time purchase removes the banner ads for good. Ads never '
            'appear inside the sourced coverage.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: s.busy || !s.storeAvailable ? null : c.buy,
            child: Text(
              s.busy
                  ? 'Working…'
                  : s.price == null
                      ? 'Remove ads'
                      : 'Remove ads — ${s.price}',
            ),
          ),
          if (!s.storeAvailable && !s.busy)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'The store isn\'t available right now.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: s.busy ? null : c.restore,
            child: const Text('Restore purchases'),
          ),
        ],
      ),
    );
  }
}

/// Google UMP "Privacy options", shown only where regulation requires it,
/// and only once UMP has actually gathered this session's consent info:
/// asking earlier reads "unknown", and opening the form then does nothing.
class _PrivacyOptionsTile extends ConsumerStatefulWidget {
  const _PrivacyOptionsTile();

  @override
  ConsumerState<_PrivacyOptionsTile> createState() =>
      _PrivacyOptionsTileState();
}

class _PrivacyOptionsTileState extends ConsumerState<_PrivacyOptionsTile> {
  late final Future<bool> _required = () async {
    final AdsService ads = ref.read(adsServiceProvider);
    if (!await ads.consentGathered) return false;
    return ads.privacyOptionsRequired();
  }();

  @override
  Widget build(BuildContext context) {
    if (ref.watch(adFreeOwnedProvider)) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: _required,
      builder: (BuildContext context, AsyncSnapshot<bool> snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return ListTile(
          leading: const Icon(Icons.tune),
          title: const Text('Ad privacy options'),
          onTap: () => ref.read(adsServiceProvider).showPrivacyOptions(),
        );
      },
    );
  }
}
