import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sides/core/constants/copy.dart';
import 'package:sides/features/digest/data/digest_cache.dart';
import 'package:sides/features/digest/domain/digest.dart';
import 'package:sides/features/story/presentation/widgets/story_detail_view.dart';

import '../fixtures/fixtures.dart';
import '../helpers/pump_app.dart';

/// Code review M3 (fix round 2): a story whose analysis failed ships with
/// empty arrays and `validation: {kept: 0}`. It must never read as "None
/// found" / "No contradictions found" — that is a claim about an analysis
/// that never ran.
void main() {
  const String failedIndex = 'failed';

  /// The sample digest with story 2's analysis stripped the way
  /// pipeline/sides_pipeline/digest.py ships a failed story.
  Map<String, Object?> digestWithFailedStory2() {
    final Map<String, Object?> json = sampleDigestJson();
    final Map<String, Object?> s =
        (json['stories']! as List<Object?>)[1]! as Map<String, Object?>;
    for (final String k in <String>[
      'agreed_facts',
      'framing',
      'omissions',
      'contested_claims',
      'opinion',
      'framing_by_bloc',
      'east_west_contradictions',
    ]) {
      s[k] = <Object?>[];
    }
    s['validation'] = <String, Object?>{
      'kept': 0,
      'dropped_by_reason': <String, Object?>{},
    };
    return json;
  }

  TestHarness harnessFor(Map<String, Object?> json) => TestHarness(
        cache: InMemoryDigestCache(
          CachedDigest(
            body: jsonEncode(json),
            fetchedAt: sampleNow.subtract(const Duration(minutes: 15)),
            etag: '"$failedIndex"',
          ),
        ),
      );

  test('the model flags it; an analysed story and a legacy file do not', () {
    final Map<String, Object?> json = digestWithFailedStory2();
    final Digest d = Digest.fromJson(json);
    expect(d.stories[1].analysisUnavailable, isTrue);
    expect(d.stories[0].analysisUnavailable, isFalse);
    // An older file without `validation` renders as before.
    ((json['stories']! as List<Object?>)[1]! as Map<String, Object?>)
        .remove('validation');
    expect(Digest.fromJson(json).stories[1].analysisUnavailable, isFalse);
  });

  // A tall phone surface, so the detail ListView builds every section: a
  // finder never sees an unbuilt lazy child, which would make an "absent"
  // assertion pass for the wrong reason.
  const Size tallPhone = Size(390, 6000);

  for (final String axis in <String>['', '?axis=bloc']) {
    testWidgets('failed story ($axis): notice, no "none found" lines',
        (WidgetTester tester) async {
      final Map<String, Object?> json = digestWithFailedStory2();
      final Story s = Digest.fromJson(json).stories[1];
      await pumpSidesApp(
        tester,
        harness: harnessFor(json),
        initialLocation: '/story/${s.id}$axis',
        size: tallPhone,
      );

      // The absences first: they are the regression (M3), the notice second.
      expect(find.text(Copy.noneFound), findsNothing);
      expect(find.text(Copy.noContradictions), findsNothing);
      expect(find.byKey(StoryDetailView.noContradictionsKey), findsNothing);
      expect(find.byKey(StoryDetailView.analysisUnavailableKey),
          findsOneWidget);
      expect(find.text(Copy.analysisUnavailable), findsOneWidget);
      // Coverage and sources still show.
      expect(find.text('${Copy.sources} (${s.articles.length})'),
          findsOneWidget);
      expect(find.text(s.title), findsWidgets);
    });
  }

  testWidgets('an analysed story with an empty section still says none found',
      (WidgetTester tester) async {
    final Map<String, Object?> json = sampleDigestJson();
    final Story s = Digest.fromJson(json).stories[0];
    await pumpSidesApp(
      tester,
      harness: harnessFor(json),
      initialLocation: '/story/${s.id}?axis=bloc',
      size: tallPhone,
    );
    expect(find.byKey(StoryDetailView.analysisUnavailableKey), findsNothing);
    expect(s.contradictions, isEmpty); // precondition of the sample
    expect(find.text(Copy.noContradictions), findsOneWidget);
  });
}
