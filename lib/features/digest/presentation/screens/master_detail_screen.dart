import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/config/app_config.dart';
import '../../../../shared/widgets/message_state.dart';
import '../../../ads/presentation/ad_banner_slot.dart';
import '../../../story/presentation/providers/story_view_controller.dart';
import '../../../story/presentation/widgets/story_detail_view.dart';
import '../../domain/digest.dart';
import '../providers/digest_controller.dart';
import '../widgets/digest_list_view.dart';

/// The master list's scroll offset, shared by the two route pages that can
/// host the tablet layout (`/` and `/story/:id`), so the list does not jump
/// back to the top on the first selection or on back.
class MasterListScrollMemory {
  double offset = 0;
}

final Provider<MasterListScrollMemory> masterListScrollProvider =
    Provider<MasterListScrollMemory>((Ref ref) => MasterListScrollMemory());

/// Tablet layout (≥ [LayoutSize.mediumMin] dp): the digest list in a fixed
/// pane on the left ([listPaneWidthFor]: 360 dp, or 320 dp below 900 dp),
/// the selected story on the right.
///
/// The selection is the route: `/` shows story 1, `/story/:id` shows that
/// story. Tapping a story calls `context.go`; between stories the route's
/// page (keyed by the `/story/:id` pattern) updates in place, so nothing is
/// pushed and nothing animates, while the URL, deep links and back work.
/// The first selection from `/` adds that one story page over `/` (with no
/// transition), which is what system back returns from.
class MasterDetailScreen extends ConsumerStatefulWidget {
  const MasterDetailScreen({
    super.key,
    this.selectedStoryId,
    this.initialAxis = PerspectiveAxis.lean,
  });

  /// Null on `/`: the first story of the digest is shown.
  final String? selectedStoryId;
  final PerspectiveAxis initialAxis;

  static const double listPaneWidth = 360;

  /// Below [narrowBelow] dp the list pane shrinks so the detail pane keeps
  /// room for a readable column (744 dp → 320 + 1 + 423).
  static const double narrowListPaneWidth = 320;
  static const double narrowBelow = 900;

  static double listPaneWidthFor(double windowWidth) =>
      windowWidth < narrowBelow ? narrowListPaneWidth : listPaneWidth;
  static const Key listPaneKey = Key('master-list-pane');
  static const Key detailPaneKey = Key('master-detail-pane');

  @override
  ConsumerState<MasterDetailScreen> createState() => _MasterDetailScreenState();
}

class _MasterDetailScreenState extends ConsumerState<MasterDetailScreen> {
  late final MasterListScrollMemory _memory = ref.read(
    masterListScrollProvider,
  );
  late final ScrollController _list = ScrollController(
    initialScrollOffset: _memory.offset,
  )..addListener(_remember);

  void _remember() {
    if (_list.hasClients) _memory.offset = _list.offset;
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Digest? digest = ref.watch(
      digestControllerProvider.select((DigestState s) => s.digest),
    );
    final String? requested = widget.selectedStoryId;
    final Story? story = digest == null
        ? null
        : requested == null
        ? digest.stories.firstOrNull
        : digest.story(requested);

    void open(Story s) {
      if (requested != null && s.id == requested) return;
      // Carry the axis the reader is on to the next story.
      final PerspectiveAxis axis = story == null
          ? PerspectiveAxis.lean
          : ref.read(storyViewProvider(story.id)).axisOr(widget.initialAxis);
      context.go(Routes.story(s.id, axis: axis));
    }

    final Widget detail;
    if (digest == null) {
      detail = const MessageState(
        icon: Icons.view_sidebar_outlined,
        title: 'No story selected',
        message: 'Today\'s stories will appear here once the digest loads.',
      );
    } else if (story == null) {
      detail = const MessageState(
        icon: Icons.article_outlined,
        title: 'Story not available',
        message:
            'This story isn\'t in the current digest any more. '
            'Choose one of today\'s stories from the list.',
      );
    } else {
      detail = StoryDetailView(
        // A fresh view (scrolled to the top) per story; the reader's axis
        // and tab live in storyViewProvider, not in this widget.
        key: ValueKey<String>('detail-${story.id}'),
        story: story,
        digest: digest,
        initialAxis: widget.initialAxis,
      );
    }

    return Scaffold(
      appBar: AppBar(
        // Selecting a story never stacks pages here; system back still pops.
        automaticallyImplyLeading: false,
        title: const Text(AppConfig.appName),
        actions: <Widget>[
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            key: MasterDetailScreen.listPaneKey,
            width: MasterDetailScreen.listPaneWidthFor(
              MediaQuery.sizeOf(context).width,
            ),
            child: FocusTraversalGroup(
              child: Semantics(
                container: true,
                label: 'Today\'s stories',
                explicitChildNodes: true,
                child: DigestListView(
                  scrollController: _list,
                  selectedStoryId: story?.id,
                  onOpenStory: open,
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: FocusTraversalGroup(
              child: Column(
                key: MasterDetailScreen.detailPaneKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: detail),
                  // Ads sit under the detail pane only, never beside the list.
                  if (story != null)
                    const SafeArea(
                      top: false,
                      left: false,
                      child: AdBannerSlot(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
