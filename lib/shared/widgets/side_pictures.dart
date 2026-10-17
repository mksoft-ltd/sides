import 'package:flutter/material.dart';

import '../../core/constants/copy.dart';
import '../../core/theme/app_theme.dart';
import '../../features/digest/domain/digest.dart';
import 'article_thumb.dart';

/// One picture per side, side by side: how each lean illustrated the story.
/// For each lean present (left, centre, right) the first article with a
/// feed image is used, preferring the articles that side's headline quotes
/// come from. Shown only when at least two sides have a picture, so Sides
/// never puts a single outlet's photo on a story. Each tile is labelled with
/// its side and outlet; the side's colour runs under it.
class SidePictures extends StatelessWidget {
  const SidePictures({
    super.key,
    required this.story,
    required this.digest,
    this.labelColor,
  });

  final Story story;
  final Digest digest;
  final Color? labelColor;

  static const Key stripKey = Key('side-pictures');

  /// (lean, article) for each lean that has a picture, in Left · Centre ·
  /// Right order.
  static List<(Lean, Article)> pick(Story story, Digest digest) {
    final List<(Lean, Article)> out = <(Lean, Article)>[];
    for (final Lean l in Lean.values) {
      bool ofLean(Article a) => digest.outlet(a.outletId)?.lean == l;
      final List<Article> quoted = <Article>[
        for (final HeadlineQuote q
            in story.framingFor(l)?.headlineQuotes ?? const <HeadlineQuote>[])
          if (story.article(q.articleId) case final Article a) a,
      ];
      final Article? hit = <Article>[
        ...quoted,
        ...story.articles.where(ofLean),
      ].where((Article a) => a.imageUrl != null && ofLean(a)).firstOrNull;
      if (hit != null) out.add((l, hit));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final List<(Lean, Article)> picks = pick(story, digest);
    if (picks.length < 2) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final PerspectiveColors colors = PerspectiveColors.of(context);
    final Color muted = labelColor ?? theme.colorScheme.onSurfaceVariant;
    return Semantics(
      key: stripKey,
      container: true,
      label: Copy.sidePicturesLabel(<String>[
        for (final (Lean l, Article a) in picks)
          '${l.label}: ${digest.outlet(a.outletId)?.name ?? a.outletId}',
      ]),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            const double gap = 8;
            final double w = (c.maxWidth - gap * (picks.length - 1)) / picks.length;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (int i = 0; i < picks.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: gap),
                  SizedBox(
                    width: w,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        ArticleThumb(
                          article: picks[i].$2,
                          outlet: digest.outlet(picks[i].$2.outletId),
                          width: w,
                          height: w * 0.62,
                          radius: 10,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: colors.forLean(picks[i].$1),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${picks[i].$1.label} · '
                          '${digest.outlet(picks[i].$2.outletId)?.name ?? picks[i].$2.outletId}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
