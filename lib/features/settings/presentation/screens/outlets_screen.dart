import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/copy.dart';
import '../../../../shared/widgets/message_state.dart';
import '../../../digest/domain/digest.dart';
import '../../../digest/presentation/providers/digest_controller.dart';
import '../../../story/presentation/widgets/sources_list.dart';

/// Every outlet in the current digest with its tags and rating basis.
class OutletsScreen extends ConsumerWidget {
  const OutletsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Digest? digest =
        ref.watch(digestControllerProvider.select((DigestState s) => s.digest));
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Outlets and ratings')),
      body: digest == null
          ? const MessageState(
              icon: Icons.newspaper_outlined,
              title: 'No outlet list yet',
              message: 'The outlet list appears once a digest has loaded.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: <Widget>[
                Text(Copy.ratingBasis, style: theme.textTheme.bodyMedium),
                for (final Bloc b in Bloc.values) ...<Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 24, bottom: 4),
                    child: Semantics(
                      header: true,
                      child: Text(Copy.blocGroup(b),
                          style: theme.textTheme.titleMedium),
                    ),
                  ),
                  for (final Outlet o in _sorted(digest.outlets, b))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('${o.name} · ${o.country}',
                              style: theme.textTheme.titleSmall),
                          const SizedBox(height: 6),
                          OutletTags(outlet: o),
                          const SizedBox(height: 6),
                          Text(
                            o.ratingBasis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
    );
  }

  static List<Outlet> _sorted(List<Outlet> all, Bloc b) => all
      .where((Outlet o) => o.bloc == b)
      .toList()
    ..sort((Outlet x, Outlet y) {
      final int c = (x.lean?.index ?? 9).compareTo(y.lean?.index ?? 9);
      return c != 0 ? c : x.name.compareTo(y.name);
    });
}
