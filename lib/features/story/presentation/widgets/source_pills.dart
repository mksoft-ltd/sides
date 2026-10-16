import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/copy.dart';
import '../../../../core/launcher/link_launcher.dart';
import '../../../digest/domain/digest.dart';
import 'sources_list.dart';

/// Opens an article in the external browser, with a snackbar on failure.
Future<void> openArticle(BuildContext context, WidgetRef ref, Article a) async {
  final Uri? uri = Uri.tryParse(a.url);
  final bool ok = uri != null && await ref.read(linkLauncherProvider).open(uri);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Couldn\'t open the article.')),
    );
  }
}

/// The articles behind a point, in citation order, each id once, ids that
/// are not articles of this story skipped (the model layer already strips
/// them; this guards again).
List<Article> resolveArticles(Story story, List<String> ids) {
  final Set<String> seen = <String>{};
  return <Article>[
    for (final String id in ids)
      if (seen.add(id))
        if (story.article(id) case final Article a) a,
  ];
}

/// The first article of each outlet, in citation order.
List<Article> distinctOutlets(List<Article> articles) {
  final Set<String> seen = <String>{};
  return <Article>[
    for (final Article a in articles)
      if (seen.add(a.outletId)) a,
  ];
}

/// "7 sources ›": the one link under a point. Tapping it opens
/// [SourcesSheet], which lists every article behind the point. Text, not a
/// row of pills, so a paragraph reads as a paragraph.
class SourcesLink extends StatelessWidget {
  const SourcesLink({
    super.key,
    required this.ids,
    required this.story,
    required this.digest,
    this.label,
  });

  final List<String> ids;
  final Story story;
  final Digest digest;

  /// Replaces "N sources" (e.g. "Stated by 3 outlets").
  final String? label;

  static String semanticsLabelFor(String label) =>
      '$label. Shows the articles behind this point.';

  @override
  Widget build(BuildContext context) {
    final List<Article> articles = resolveArticles(story, ids);
    if (articles.isEmpty) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final String text =
        label ?? Copy.sourcesLink(distinctOutlets(articles).length);
    final Color color = theme.colorScheme.primary;
    // The whole line is the tap target (a generous one), text at the left.
    return Semantics(
      button: true,
      label: semanticsLabelFor(text),
      excludeSemantics: true,
      onTap: () => _open(context),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _open(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  text,
                  style: theme.textTheme.labelLarge?.copyWith(color: color),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) =>
      showSourcesSheet(context, story: story, digest: digest, ids: ids);
}

/// Opens the sources of a point in a bottom sheet.
Future<void> showSourcesSheet(
  BuildContext context, {
  required Story story,
  required Digest digest,
  required List<String> ids,
  String? first,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) => SourcesSheet(
        story: story,
        digest: digest,
        ids: ids,
        first: first,
      ),
    );

/// "Sources for this point": every article behind one point, outlet and
/// headline visible, each row opening the original article.
class SourcesSheet extends StatelessWidget {
  const SourcesSheet({
    super.key,
    required this.story,
    required this.digest,
    required this.ids,
    this.first,
  });

  final Story story;
  final Digest digest;
  final List<String> ids;

  /// The article to list first.
  final String? first;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Article> articles = resolveArticles(story, ids);
    if (first != null) {
      final int i = articles.indexWhere((Article a) => a.id == first);
      if (i > 0) articles.insert(0, articles.removeAt(i));
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: Text(
                    Copy.sourcesForPoint,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  Copy.sourcesSheetCount(articles.length),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              itemCount: articles.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (BuildContext context, int i) => SourceTile(
                article: articles[i],
                outlet: digest.outlet(articles[i].outletId),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
