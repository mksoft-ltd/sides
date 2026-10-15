import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/launcher/link_launcher.dart';
import '../../../../core/layout/breakpoints.dart';
import '../../../digest/domain/digest.dart';

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

/// One tappable source: "Outlet — headline", opening the original article.
class SourceChip extends ConsumerWidget {
  const SourceChip({
    super.key,
    required this.article,
    required this.outlet,
  });

  final Article article;
  final Outlet? outlet;

  static String semanticsLabelFor(Article a, Outlet? o) =>
      'Source: ${o?.name ?? a.outletId} — ${a.headline}. Opens in your browser.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    // Tablets have room for most full headlines; phones keep two lines.
    final int maxLines = LayoutSize.of(context) == LayoutSize.compact ? 2 : 3;
    return Semantics(
      button: true,
      link: true,
      label: semanticsLabelFor(article, outlet),
      excludeSemantics: true,
      // excludeSemantics drops the InkWell's own action, so re-expose it or
      // TalkBack and Switch Access cannot open the article (F2).
      onTap: () => openArticle(context, ref, article),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => openArticle(context, ref, article),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: outlet?.name ?? article.outletId,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(text: ' — ${article.headline}'),
                        ],
                      ),
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.open_in_new, size: 16, color: cs.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sources of one point. Shows the first [initialCount], then a button
/// to reveal the rest, so a fact backed by fifteen outlets stays readable.
class SourceChipList extends StatefulWidget {
  const SourceChipList({
    super.key,
    required this.ids,
    required this.story,
    required this.digest,
    this.initialCount = 3,
  });

  final List<String> ids;
  final Story story;
  final Digest digest;
  final int initialCount;

  @override
  State<SourceChipList> createState() => _SourceChipListState();
}

class _SourceChipListState extends State<SourceChipList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final List<Article> articles = <Article>[
      for (final String id in widget.ids)
        if (widget.story.article(id) case final Article a) a,
    ];
    final int hidden = articles.length - widget.initialCount;
    final List<Article> shown = _expanded || hidden <= 0
        ? articles
        : articles.sublist(0, widget.initialCount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final Article a in shown)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SourceChip(
              article: a,
              outlet: widget.digest.outlet(a.outletId),
            ),
          ),
        if (hidden > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded
                    ? 'Show fewer sources'
                    : 'Show $hidden more ${hidden == 1 ? 'source' : 'sources'}',
              ),
            ),
          ),
      ],
    );
  }
}
