import 'package:flutter/widgets.dart';

/// Width classes from the plan. Phase 4 builds the compact (phone) layout;
/// phase 5 adds master-detail at [medium] and side-by-side perspective
/// columns at [expanded]. Screens are split into a scaffold plus a reusable
/// body (`DigestListView`, `StoryDetailView`) so a tablet layout can host
/// both bodies at once without rewriting either.
enum LayoutSize {
  compact,
  medium,
  expanded;

  static const double mediumMin = 840;
  static const double expandedMin = 1100;

  static LayoutSize of(BuildContext context) {
    final double w = MediaQuery.sizeOf(context).width;
    if (w >= expandedMin) return LayoutSize.expanded;
    if (w >= mediumMin) return LayoutSize.medium;
    return LayoutSize.compact;
  }
}
