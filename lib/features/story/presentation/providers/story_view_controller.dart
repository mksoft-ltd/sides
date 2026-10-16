import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show NotifierProviderFamily;

enum PerspectiveAxis { lean, bloc }

/// What the reader has chosen on one story page: the comparison axis. It
/// lives in a provider (not in widget state) so that a rotation or window
/// resize that swaps the phone page for the tablet master-detail layout, or
/// stacked sides for columns, keeps the reader's place.
///
/// Every side is always on the page (stacked, or in columns), so there is no
/// per-side tab to remember.
@immutable
class StoryViewState {
  const StoryViewState({this.axis});

  /// Null until the reader switches axis; the route's `?axis=` applies then.
  final PerspectiveAxis? axis;

  PerspectiveAxis axisOr(PerspectiveAxis initial) => axis ?? initial;
}

/// One state per story id. Auto-disposed when no view shows that story, so
/// opening a story afresh starts from the route's axis. A layout swap
/// re-subscribes in the same frame, so the state survives rotation.
class StoryViewController extends Notifier<StoryViewState> {
  StoryViewController(this.storyId);

  final String storyId;

  @override
  StoryViewState build() => const StoryViewState();

  void setAxis(PerspectiveAxis axis) => state = StoryViewState(axis: axis);
}

final NotifierProviderFamily<StoryViewController, StoryViewState, String>
storyViewProvider = NotifierProvider.autoDispose
    .family<StoryViewController, StoryViewState, String>(
      StoryViewController.new,
    );
