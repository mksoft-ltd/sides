import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/copy.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/outlet_avatar.dart';
import '../../../../shared/widgets/tag.dart';
import '../../../digest/domain/digest.dart';
import 'source_pills.dart';

/// Lean / bloc / region / ownership tags for an outlet.
class OutletTags extends StatelessWidget {
  const OutletTags({super.key, required this.outlet});
  final Outlet outlet;

  @override
  Widget build(BuildContext context) {
    final PerspectiveColors c = PerspectiveColors.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        if (outlet.lean case final Lean l)
          Tag(l.label, color: c.forLean(l))
        else
          const Tag(Copy.noLeanRating),
        Tag(outlet.bloc.label, color: c.forBloc(outlet.bloc)),
        Tag(outlet.regionLabel),
        if (outlet.ownership != Ownership.independent)
          Tag(
            outlet.isStateControlled ? 'state media' : outlet.ownership.label,
            emphasised: outlet.isStateControlled,
          ),
      ],
    );
  }
}

/// Every article in the story: outlet, tags, headline, link. Western
/// outlets first (by lean), then Eastern, so the list reads like the axes.
class SourcesList extends StatelessWidget {
  const SourcesList({super.key, required this.story, required this.digest});
  final Story story;
  final Digest digest;

  @override
  Widget build(BuildContext context) {
    int order(Article a) {
      final Outlet? o = digest.outlet(a.outletId);
      if (o == null) return 99;
      return o.bloc.index * 10 + (o.lean?.index ?? 5);
    }

    final List<Article> sorted = <Article>[...story.articles]
      ..sort((Article a, Article b) {
        final int c = order(a).compareTo(order(b));
        return c != 0 ? c : a.outletId.compareTo(b.outletId);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < sorted.length; i++) ...<Widget>[
          if (i > 0) const Divider(),
          SourceTile(
            article: sorted[i],
            outlet: digest.outlet(sorted[i].outletId),
          ),
        ],
      ],
    );
  }
}

/// One article: outlet name, tags, headline, opening in the browser. Used by
/// the Sources section and by the per-point sources sheet.
class SourceTile extends ConsumerWidget {
  const SourceTile({super.key, required this.article, required this.outlet});
  final Article article;
  final Outlet? outlet;

  static String semanticsLabelFor(Article a, Outlet? o) =>
      'Source: ${o?.name ?? a.outletId} — ${a.headline}. Opens in your browser.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final Outlet? o = outlet;
    return Semantics(
      button: true,
      link: true,
      label: <String>[
        semanticsLabelFor(article, o),
        if (o?.isStateControlled ?? false) 'State media.',
      ].join(' '),
      excludeSemantics: true,
      // excludeSemantics drops the InkWell's own action, so re-expose it or
      // TalkBack and Switch Access cannot open the article (F2).
      onTap: () => openArticle(context, ref, article),
      child: InkWell(
        onTap: () => openArticle(context, ref, article),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              OutletAvatar(outlet: o, fallbackName: article.outletId, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      o?.name ?? article.outletId,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    if (o != null) OutletTags(outlet: o),
                    const SizedBox(height: 8),
                    Text(article.headline, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.open_in_new,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
