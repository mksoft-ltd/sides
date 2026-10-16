import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sides/core/constants/copy.dart';
import 'package:sides/features/digest/domain/digest.dart';
import 'package:sides/features/story/presentation/widgets/story_detail_view.dart';
import 'package:sides/shared/widgets/motion.dart';
import 'package:sides/shared/widgets/section.dart';

import '../fixtures/fixtures.dart';
import '../helpers/pump_app.dart';

/// Motion on the story page: a staggered reveal when a story opens, a
/// highlight where a jump lands, and none of it when the platform asks for
/// reduced motion.
void main() {
  final Digest digest = sampleDigest();
  final Story s2 = digest.stories[1];

  Finder detailScrollable() => find
      .descendant(
        of: find.byType(StoryDetailView),
        matching: find.byType(Scrollable),
      )
      .first;

  testWidgets('the page reveals in a stagger: blocks start transparent and '
      'end opaque', (WidgetTester tester) async {
    // First frame only: the animations have just started.
    await pumpSidesApp(tester, initialLocation: '/story/${s2.id}', settle: false);
    final Iterable<FadeTransition> fades = tester.widgetList<FadeTransition>(
      find.descendant(
        of: find.byType(Reveal),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fades.length, greaterThan(4));
    // Later blocks are delayed, so at least one is still fully transparent.
    expect(fades.any((FadeTransition f) => f.opacity.value == 0), isTrue);
    await tester.pumpAndSettle();
    for (final FadeTransition f in tester.widgetList<FadeTransition>(
      find.descendant(
        of: find.byType(Reveal),
        matching: find.byType(FadeTransition),
      ),
    )) {
      expect(f.opacity.value, 1);
    }
  });

  testWidgets('a jump highlights the section it lands on, then lets go',
      (WidgetTester tester) async {
    await pumpSidesApp(tester, initialLocation: '/story/${s2.id}');
    Section contested() => tester.widget<Section>(
          find.ancestor(
            of: find.text(Copy.contested),
            matching: find.byType(Section),
          ),
        );
    expect(contested().highlighted, isFalse);
    final Finder chip = find.byKey(const ValueKey<String>('jump-contested'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(contested().highlighted, isTrue);
    // The flash timer schedules no frame of its own: advance past it.
    await tester.pump(Motion.flash + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(contested().highlighted, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching axis keeps both axes anchors distinct and settles',
      (WidgetTester tester) async {
    await pumpSidesApp(tester, initialLocation: '/story/${s2.id}');
    final Finder bloc = find.descendant(
      of: find.byType(SegmentedButton<PerspectiveAxis>),
      matching: find.text(Copy.axisBloc),
    );
    await tester.ensureVisible(bloc);
    await tester.pumpAndSettle();
    await tester.tap(bloc);
    // Mid-transition both axes' sections are in the tree: no duplicate
    // GlobalKey error, and the page still lays out.
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.byType(AxisSwitcher), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text(Copy.blocGroup(Bloc.west)), findsWidgets);
    expect(find.text(Copy.leanGroup(Lean.left)), findsNothing);
    await tester.scrollUntilVisible(
      find.text(Copy.contradictions),
      200,
      scrollable: detailScrollable(),
    );
    expect(find.text(Copy.contradictions), findsOneWidget);
  });

  testWidgets('reduced motion: everything is in place on the first frame',
      (WidgetTester tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpSidesApp(tester, initialLocation: '/story/${s2.id}', settle: false);
    for (final FadeTransition f in tester.widgetList<FadeTransition>(
      find.descendant(
        of: find.byType(Reveal),
        matching: find.byType(FadeTransition),
      ),
    )) {
      expect(f.opacity.value, 1);
    }
    // Material chips carry their own AnimatedSwitcher; ours is the one with
    // the axis-switch duration, and it is bypassed under reduced motion.
    expect(
      find.byWidgetPredicate(
        (Widget w) => w is AnimatedSwitcher && w.duration == Motion.axisSwitch,
      ),
      findsNothing,
    );
    expect(find.byType(CountUp), findsWidgets);
  });
}
