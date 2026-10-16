import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/copy.dart';
import '../../../../core/text/quotes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../digest/domain/digest.dart';
import 'source_pills.dart';

/// Where a side block draws its colour rail: down the left (stacked sides on
/// phones) or along the top (side-by-side columns on wide tablets).
enum RailSide { left, top }

/// One side's content, framed by a rail in the side's colour and headed by
/// the side's name and outlet count, so the reader always knows whose
/// coverage they are looking at while scrolling.
class SideBlock extends StatelessWidget {
  const SideBlock({
    super.key,
    required this.color,
    required this.label,
    required this.child,
    this.count,
    this.rail = RailSide.left,
  });

  final Color color;
  final String label;
  final int? count;
  final Widget child;
  final RailSide rail;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        padding: rail == RailSide.left
            ? const EdgeInsets.only(left: 12)
            : const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
          border: rail == RailSide.left
              ? Border(left: BorderSide(color: color, width: 3))
              : Border(top: BorderSide(color: color, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SideHeading(label: label, color: color, count: count),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// Colour dot, side name (announced as a header) and outlet count.
class SideHeading extends StatelessWidget {
  const SideHeading({
    super.key,
    required this.label,
    required this.color,
    this.count,
  });

  final String label;
  final Color color;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(label, style: theme.textTheme.titleSmall),
          ),
        ),
        if (count != null) ...<Widget>[
          const SizedBox(width: 8),
          Text(
            Copy.outletCount(count!),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// A point and its sources. Never rendered without at least one source:
/// the model layer already drops unsourced items, and this guards again.
class PointTile extends StatelessWidget {
  const PointTile({
    super.key,
    required this.point,
    required this.story,
    required this.digest,
  });

  final SourcedPoint point;
  final Story story;
  final Digest digest;

  @override
  Widget build(BuildContext context) {
    if (!point.sources.any((String id) => story.article(id) != null)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(point.text, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 2),
          SourcePills(ids: point.sources, story: story, digest: digest),
        ],
      ),
    );
  }
}

/// A verbatim quote from a headline or feed summary, with the outlet it is
/// from. The row itself opens the article: the quote is the evidence, so
/// there is nothing to repeat beneath it.
class QuoteRow extends ConsumerWidget {
  const QuoteRow({
    super.key,
    required this.quote,
    required this.story,
    required this.digest,
  });

  final HeadlineQuote quote;
  final Story story;
  final Digest digest;

  static String semanticsLabelFor(HeadlineQuote q, Outlet? o, Article a) =>
      'Quote from ${o?.name ?? a.outletId}, '
      '${q.field == QuoteField.headline ? 'headline' : 'summary'}: '
      '${q.quote}. Opens the article in your browser.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Article? article = story.article(quote.articleId);
    if (article == null) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final Outlet? outlet = digest.outlet(article.outletId);
    return Semantics(
      button: true,
      link: true,
      label: semanticsLabelFor(quote, outlet, article),
      excludeSemantics: true,
      onTap: () => openArticle(context, ref, article),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => openArticle(context, ref, article),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      Quotes.wrap(quote.quote),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Copy.quoteOrigin(
                        outlet?.name ?? article.outletId,
                        quote.field,
                      ),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(
                  Icons.open_in_new,
                  size: 16,
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

/// A side's headline quotes, one row each, separated by hairlines.
class QuoteList extends StatelessWidget {
  const QuoteList({
    super.key,
    required this.quotes,
    required this.story,
    required this.digest,
  });

  final List<HeadlineQuote> quotes;
  final Story story;
  final Digest digest;

  @override
  Widget build(BuildContext context) {
    if (quotes.isEmpty) return const NoneFound();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < quotes.length; i++) ...<Widget>[
          if (i > 0) const Divider(),
          QuoteRow(quote: quotes[i], story: story, digest: digest),
        ],
      ],
    );
  }
}

/// A side's emphasis points.
class PointList extends StatelessWidget {
  const PointList({
    super.key,
    required this.points,
    required this.story,
    required this.digest,
  });

  final List<SourcedPoint> points;
  final Story story;
  final Digest digest;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const NoneFound();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final SourcedPoint p in points)
          PointTile(point: p, story: story, digest: digest),
      ],
    );
  }
}

/// A claim some outlets state and others dispute, with both sets of
/// outlets named. The two sides are disjoint outlet sets (validator rule).
class ContestedClaimCard extends StatelessWidget {
  const ContestedClaimCard({
    super.key,
    required this.claim,
    required this.story,
    required this.digest,
  });

  final ContestedClaim claim;
  final Story story;
  final Digest digest;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Color muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(claim.claim, style: t.bodyLarge),
            const SizedBox(height: 10),
            Text(
              Copy.assertedBy,
              style: t.labelMedium?.copyWith(color: muted),
            ),
            SourcePills(ids: claim.assertedBy, story: story, digest: digest),
            const SizedBox(height: 6),
            Text(
              Copy.disputedBy,
              style: t.labelMedium?.copyWith(color: muted),
            ),
            SourcePills(ids: claim.disputedBy, story: story, digest: digest),
          ],
        ),
      ),
    );
  }
}

/// One topic with its West and East statements: stacked (phones), or, with
/// [sideBySide], the topic spanning both columns and West / East in two
/// aligned columns that line up with the bloc columns above.
class ContradictionCard extends StatelessWidget {
  const ContradictionCard({
    super.key,
    required this.contradiction,
    required this.story,
    required this.digest,
    this.sideBySide = false,
  });

  final Contradiction contradiction;
  final Story story;
  final Digest digest;
  final bool sideBySide;

  /// Matches `StoryDetailView.columnGap` so rows align with the columns.
  static const double columnGap = 16;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PerspectiveColors colors = PerspectiveColors.of(context);
    Widget side(Bloc b, SourcedPoint p) => SideBlock(
      key: ValueKey<String>('contradiction-${b.wire}'),
      color: colors.forBloc(b),
      label: Copy.blocGroup(b),
      child: PointTile(point: p, story: story, digest: digest),
    );
    final Widget topic = Semantics(
      header: sideBySide,
      child: Text(contradiction.topic, style: theme.textTheme.titleSmall),
    );
    if (sideBySide) {
      // No card inset here: the two halves sit at exactly the x positions
      // of the West and East columns above, so each row reads across.
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Divider(),
            const SizedBox(height: 12),
            topic,
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: side(Bloc.west, contradiction.west)),
                const SizedBox(width: columnGap),
                Expanded(child: side(Bloc.east, contradiction.east)),
              ],
            ),
          ],
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            topic,
            const SizedBox(height: 12),
            side(Bloc.west, contradiction.west),
            const SizedBox(height: 12),
            side(Bloc.east, contradiction.east),
          ],
        ),
      ),
    );
  }
}

/// The neutral "nothing here" line.
class NoneFound extends StatelessWidget {
  const NoneFound({super.key, this.text = Copy.noneFound});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
}
