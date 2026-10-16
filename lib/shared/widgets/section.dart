import 'package:flutter/material.dart';

/// A titled block on the story page. Give it a [GlobalKey] to make it a
/// jump-bar target.
class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.icon,
    this.tinted = false,
    this.highlighted = false,
  });

  /// Briefly true after a jump lands here: a soft tint that fades away.
  final bool highlighted;

  final String title;

  /// Leading icon in the heading, in the primary colour.
  final IconData? icon;
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 20, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
            ),
          ],
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(top: 28),
      padding: EdgeInsets.symmetric(horizontal: highlighted ? 8 : 0),
      transform: Matrix4.translationValues(highlighted ? -8 : 0, 0, 0),
      decoration: BoxDecoration(
        color: highlighted
            ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.55)
            : theme.colorScheme.secondaryContainer.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(12),
      ),
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
