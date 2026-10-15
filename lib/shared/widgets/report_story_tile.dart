import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/copy.dart';
import '../../core/launcher/link_launcher.dart';

/// The `mailto:` for a story report. Built with percent-encoding (never `+`
/// for spaces, which mail apps show literally). [title] and [date] are set
/// when the report starts from a story page.
Uri storyReportMailto({String? title, String? date}) {
  final String subject = Uri.encodeComponent(Copy.reportStorySubject);
  final String body = Uri.encodeComponent(
    Copy.reportStoryBody(title: title, date: date),
  );
  return Uri(
    scheme: 'mailto',
    path: AppConfig.contactEmail,
    query: 'subject=$subject&body=$body',
  );
}

/// Opens a story report in the mail app via [LinkLauncher.compose], the
/// mailto-only path (the article path stays http/https only).
class ReportStoryTile extends ConsumerWidget {
  const ReportStoryTile({super.key, this.title, this.date});

  /// Present when opened from a story page.
  final String? title;
  final String? date;

  static const Key tileKey = Key('report-story');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool fromStory = title != null;
    return ListTile(
      key: tileKey,
      contentPadding: fromStory
          ? EdgeInsets.zero
          : null, // story page has its own padding
      leading: const Icon(Icons.flag_outlined),
      title: Text(fromStory ? Copy.reportThisStory : Copy.reportStory),
      subtitle: const Text(Copy.reportStorySubtitle),
      onTap: () async {
        final bool ok = await ref
            .read(linkLauncherProvider)
            .compose(storyReportMailto(title: title, date: date));
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text(Copy.contactFailed)));
        }
      },
    );
  }
}
