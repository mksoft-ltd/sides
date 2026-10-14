import 'package:flutter/material.dart';

import '../../../../core/constants/copy.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../digest/domain/digest.dart';
import 'source_chips.dart';

/// A point and its sources. Never rendered without at least one source:
/// the model layer already drops unsourced items, and this guards again.
class SourcedPointTile extends StatelessWidget {
  const SourcedPointTile({
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(point.text, style: Theme.of(context).textTheme.bodyLarge),
          SourceChipList(ids: point.sources, story: story, digest: digest),
        ],
      ),
    );
  }
}

/// A verbatim quote from a headline or snippet, labelled with which.
class QuoteCard extends StatelessWidget {
  const QuoteCard({
    super.key,
    required this.quote,
    required this.story,
    required this.digest,
  });

  final HeadlineQuote quote;
  final Story story;
  final Digest digest;

  @override
  Widget build(BuildContext context) {
    final Article? article = story.article(quote.articleId);
    if (article == null) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final Outlet? outlet = digest.outlet(article.outletId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.outline, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '“${quote.quote}”',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 4),
            Text(
              '${quote.field.wire} · ${outlet?.name ?? article.outletId}',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            SourceChipList(
              ids: <String>[article.id],
              story: story,
              digest: digest,
            ),
          ],
        ),
      ),
    );
  }
}

/// Headline wording + emphasis for one lean or bloc.
class FramingPanel extends StatelessWidget {
  const FramingPanel({
    super.key,
    required this.groupLabel,
    required this.quotes,
    required this.emphasis,
    required this.story,
    required this.digest,
  });

  final String groupLabel;
  final List<HeadlineQuote> quotes;
  final List<SourcedPoint> emphasis;
  final Story story;
  final Digest digest;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(groupLabel, style: t.titleMedium),
        const SizedBox(height: 12),
        Text(Copy.headlineWording, style: t.labelLarge),
        const SizedBox(height: 8),
        if (quotes.isEmpty) const _PaddedNone(),
        for (final HeadlineQuote q in quotes)
          QuoteCard(quote: q, story: story, digest: digest),
        const SizedBox(height: 4),
        Text(Copy.emphasis, style: t.labelLarge),
        const SizedBox(height: 8),
        if (emphasis.isEmpty) const _PaddedNone(),
        for (final SourcedPoint p in emphasis)
          SourcedPointTile(point: p, story: story, digest: digest),
      ],
    );
  }
}

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
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(claim.claim, style: t.bodyLarge),
          const SizedBox(height: 8),
          Text(Copy.assertedBy, style: t.labelMedium),
          SourceChipList(ids: claim.assertedBy, story: story, digest: digest),
          const SizedBox(height: 8),
          Text(Copy.disputedBy, style: t.labelMedium),
          SourceChipList(ids: claim.disputedBy, story: story, digest: digest),
        ],
      ),
    );
  }
}

/// One topic, West row then East row.
class ContradictionCard extends StatelessWidget {
  const ContradictionCard({
    super.key,
    required this.contradiction,
    required this.story,
    required this.digest,
  });

  final Contradiction contradiction;
  final Story story;
  final Digest digest;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PerspectiveColors colors = PerspectiveColors.of(context);
    Widget side(Bloc b, SourcedPoint p) => Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: colors.forBloc(b), width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(b.label, style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              SourcedPointTile(point: p, story: story, digest: digest),
            ],
          ),
        );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(contradiction.topic, style: theme.textTheme.titleSmall),
            side(Bloc.west, contradiction.west),
            side(Bloc.east, contradiction.east),
          ],
        ),
      ),
    );
  }
}

class _PaddedNone extends StatelessWidget {
  const _PaddedNone();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: NoneFound(),
      );
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
