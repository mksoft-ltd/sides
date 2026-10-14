import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show NotifierProviderFamily;

enum PerspectiveAxis { lean, bloc }

/// What the reader has chosen on one story page: the axis and the selected
/// tab on each axis. It lives in a provider (not in widget state) so that a
/// rotation or window resize that swaps the phone page for the tablet
/// master-detail layout, or the tabs for columns, keeps the reader's place.
@immutable
class StoryViewState {
  const StoryViewState({this.axis, this.leanTab = 0, this.blocTab = 0});

  /// Null until the reader switches axis; the route's `?axis=` applies then.
  final PerspectiveAxis? axis;
  final int leanTab;
  final int blocTab;

  PerspectiveAxis axisOr(PerspectiveAxis initial) => axis ?? initial;
}

/// One state per story id. Auto-disposed when no view shows that story, so
/// opening a story afresh starts from the route's axis, exactly as the phone
/// page did before. A layout swap re-subscribes in the same frame, so the
/// state survives rotation.
class StoryViewController extends Notifier<StoryViewState> {
  StoryViewController(this.storyId);

  final String storyId;

  @override
  StoryViewState build() => const StoryViewState();

  void setAxis(PerspectiveAxis axis) => state = StoryViewState(
    axis: axis,
    leanTab: state.leanTab,
    blocTab: state.blocTab,
  );

  void setLeanTab(int i) => state = StoryViewState(
    axis: state.axis,
    leanTab: i,
    blocTab: state.blocTab,
  );

  void setBlocTab(int i) => state = StoryViewState(
    axis: state.axis,
    leanTab: state.leanTab,
    blocTab: i,
  );
}

final NotifierProviderFamily<StoryViewController, StoryViewState, String>
storyViewProvider = NotifierProvider.autoDispose
    .family<StoryViewController, StoryViewState, String>(
      StoryViewController.new,
    );
