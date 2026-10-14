import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/copy.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/tag.dart';
import '../../../digest/domain/digest.dart';
import 'source_chips.dart';

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

/// Every article in the story: outlet, tags, headline, link.
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
        for (final Article a in sorted)
          _SourceTile(article: a, outlet: digest.outlet(a.outletId)),
      ],
    );
  }
}

class _SourceTile extends ConsumerWidget {
  const _SourceTile({required this.article, required this.outlet});
  final Article article;
  final Outlet? outlet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final Outlet? o = outlet;
    return Semantics(
      button: true,
      link: true,
      label: [
        SourceChip.semanticsLabelFor(article, o),
        if (o?.isStateControlled ?? false) 'State media.',
      ].join(' '),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => openArticle(context, ref, article),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(o?.name ?? article.outletId,
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    if (o != null) OutletTags(outlet: o),
                    const SizedBox(height: 6),
                    Text(article.headline, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.open_in_new,
                    size: 18, color: theme.colorScheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
