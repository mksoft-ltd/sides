import 'package:flutter/material.dart';

import '../../core/constants/copy.dart';
import '../../features/digest/domain/digest.dart';

/// "Only left-leaning outlets covered this" / "Only Western outlets covered
/// this". Computed by the pipeline from outlet tags, never by the model.
class BlindspotChips extends StatelessWidget {
  const BlindspotChips({super.key, required this.blindspot});
  final Blindspot blindspot;

  @override
  Widget build(BuildContext context) {
    if (!blindspot.any) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          if (blindspot.lean case final Lean l)
            _BlindspotChip(Copy.blindspotLean(l)),
          if (blindspot.bloc case final Bloc b)
            _BlindspotChip(Copy.blindspotBloc(b)),
        ],
      ),
    );
  }
}

class _BlindspotChip extends StatelessWidget {
  const _BlindspotChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.visibility_off_outlined,
              size: 16, color: cs.onSecondaryContainer),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: cs.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
