import 'package:flutter/material.dart';

/// A small non-interactive label ("Left", "West", "State media").
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color, this.emphasised = false});

  final String text;

  /// Accent for the leading dot; null for no dot.
  final Color? color;

  /// Stronger outline, used for the state-media tag.
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: emphasised ? cs.tertiaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: emphasised ? Border.all(color: cs.tertiary) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (color != null) ...<Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: emphasised ? cs.onTertiaryContainer : cs.onSurface,
                    fontWeight: emphasised ? FontWeight.w600 : null,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
