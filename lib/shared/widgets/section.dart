import 'package:flutter/material.dart';

/// A titled block on the story page. Give it a [GlobalKey] to make it a
/// jump-bar target.
class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.tinted = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// Opinion & analysis sits in a tinted panel so it is visibly separate
  /// from reporting.
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.titleMedium),
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 14),
        ...children,
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: tinted
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer
                    .withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: body,
            )
          : body,
    );
  }
}
