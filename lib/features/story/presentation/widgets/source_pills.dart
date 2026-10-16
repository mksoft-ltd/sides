import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/copy.dart';
import '../../../../core/launcher/link_launcher.dart';
import '../../../../shared/widgets/outlet_avatar.dart';
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

/// The sources of one point as a row of outlet pills: one pill per outlet
/// (an outlet with two articles on the point gets one pill), the first
/// [maxVisible] by citation order, the rest folded into "+N more". Each pill
/// carries the outlet's avatar (initials on its lean colour, bloc colour for
/// outlets off the lean scale), so a reader sees at a glance which sides
/// back a point.
/// Tapping any pill opens [SourcesSheet] for the point, with the tapped
/// outlet's article first; the sheet lists every article and its rows open
/// the originals.
class SourcePills extends StatelessWidget {
  const SourcePills({
    super.key,
    required this.ids,
    required this.story,
    required this.digest,
    this.maxVisible = 3,
  });

  final List<String> ids;
  final Story story;
  final Digest digest;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    final List<Article> articles = resolveArticles(story, ids);
    if (articles.isEmpty) return const SizedBox.shrink();
    final List<Article> perOutlet = distinctOutlets(articles);
    final List<Article> shown = perOutlet.length > maxVisible
        ? perOutlet.sublist(0, maxVisible)
        : perOutlet;
    final int hidden = perOutlet.length - shown.length;
    return Wrap(
      spacing: 6,
      children: <Widget>[
        for (final Article a in shown)
          SourcePill(
            article: a,
            outlet: digest.outlet(a.outletId),
            onTap: () => showSourcesSheet(
              context,
              story: story,
              digest: digest,
              ids: ids,
              first: a.id,
            ),
          ),
        if (hidden > 0)
          SourcePill.more(
            count: hidden,
            onTap: () => showSourcesSheet(
              context,
              story: story,
              digest: digest,
              ids: ids,
            ),
          ),
      ],
    );
  }
}

/// The first article of each outlet, in citation order.
List<Article> distinctOutlets(List<Article> articles) {
  final Set<String> seen = <String>{};
  return <Article>[
    for (final Article a in articles)
      if (seen.add(a.outletId)) a,
  ];
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

/// One outlet pill, or the "+N more" pill.
class SourcePill extends StatelessWidget {
  const SourcePill({
    super.key,
    required Article this.article,
    required this.outlet,
    required this.onTap,
  }) : moreCount = null;

  const SourcePill.more({super.key, required int count, required this.onTap})
      : article = null,
        outlet = null,
        moreCount = count;

  final Article? article;
  final Outlet? outlet;
  final int? moreCount;
  final VoidCallback onTap;

  static String semanticsLabelFor(Article a, Outlet? o) {
    final String side = switch (o) {
      null => '',
      Outlet(lean: final Lean l) => ', ${l.label.toLowerCase()}-leaning',
      Outlet(bloc: final Bloc b) => ', ${b.adjective}',
    };
    return 'Source: ${o?.name ?? a.outletId}$side. Shows the articles behind '
        'this point.';
  }

  static String moreSemanticsLabel(int n) =>
      '$n more ${n == 1 ? 'source' : 'sources'}. Shows every source for this '
      'point.';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Article? a = article;
    final Outlet? o = outlet;

    final String label;
    final String semanticsLabel;
    Widget? avatar;
    if (a == null) {
      label = Copy.moreSources(moreCount!);
      semanticsLabel = moreSemanticsLabel(moreCount!);
    } else {
      label = o?.name ?? a.outletId;
      semanticsLabel = semanticsLabelFor(a, o);
      avatar = OutletAvatar(outlet: o, fallbackName: a.outletId, size: 20);
    }

    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: ActionChip(
        avatar: avatar,
        labelPadding: avatar == null
            ? null
            : const EdgeInsets.only(left: 4, right: 2),
        label: Text(label),
        labelStyle: a == null
            ? theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              )
            : null,
        tooltip: a?.headline,
        onPressed: onTap,
      ),
    );
  }
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

  /// The article to list first (the pill the reader tapped).
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
