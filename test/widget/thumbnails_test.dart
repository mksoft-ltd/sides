import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sides/features/digest/data/digest_cache.dart';
import 'package:sides/features/digest/domain/digest.dart';
import 'package:sides/shared/widgets/article_thumb.dart';
import 'package:sides/shared/widgets/outlet_avatar.dart';
import 'package:sides/shared/widgets/side_pictures.dart';

import '../fixtures/fixtures.dart';
import '../helpers/pump_app.dart';

/// Feed thumbnails: https links only, one picture per side and never a lone
/// photo for a story, and the outlet's initials whenever an image is missing
/// or fails to load (widget tests cannot load network images, so every load
/// here fails and must fall back cleanly).
void main() {
  /// The sample digest with an image on every article of story 1 whose
  /// outlet is in [leans] (null = every article).
  Map<String, Object?> withImages(Set<String>? leans) {
    final Map<String, Object?> j = sampleDigestJson();
    final Map<String, String?> leanOf = <String, String?>{
      for (final Object? o in j['outlets']! as List<Object?>)
        (o! as Map<String, Object?>)['id']! as String:
            (o as Map<String, Object?>)['lean'] as String?,
    };
    final Map<String, Object?> s =
        (j['stories']! as List<Object?>).first! as Map<String, Object?>;
    for (final Object? a in s['articles']! as List<Object?>) {
      final Map<String, Object?> art = a! as Map<String, Object?>;
      final String? lean = leanOf[art['outlet_id']];
      if (leans == null || leans.contains(lean)) {
        art['image_url'] = 'https://img.example/${art['id']}.jpg';
      }
    }
    return j;
  }

  TestHarness harnessFor(Map<String, Object?> json) => TestHarness(
        cache: InMemoryDigestCache(
          CachedDigest(
            body: jsonEncode(json),
            fetchedAt: sampleNow.subtract(const Duration(minutes: 15)),
            etag: '"img"',
          ),
        ),
      );

  test('only https image links are kept', () {
    final Map<String, Object?> j = withImages(null);
    final Map<String, Object?> s =
        (j['stories']! as List<Object?>).first! as Map<String, Object?>;
    final List<Object?> arts = s['articles']! as List<Object?>;
    (arts[0]! as Map<String, Object?>)['image_url'] = 'http://img.example/a.jpg';
    (arts[1]! as Map<String, Object?>)['image_url'] = 'javascript:alert(1)';
    (arts[2]! as Map<String, Object?>)['image_url'] = 'https://u:p@img.example/a.jpg';
    final Story story = Digest.fromJson(j).stories.first;
    expect(story.articles[0].imageUrl, isNull);
    expect(story.articles[1].imageUrl, isNull);
    expect(story.articles[2].imageUrl, isNull);
    expect(story.articles[3].imageUrl, startsWith('https://img.example/'));
  });

  test('side pictures: one per lean, Left · Centre · Right order', () {
    final Digest d = Digest.fromJson(withImages(null));
    final List<(Lean, Article)> picks = SidePictures.pick(d.stories.first, d);
    expect(picks.map(((Lean, Article) p) => p.$1), <Lean>[Lean.left, Lean.centre, Lean.right]);
    for (final (Lean l, Article a) in picks) {
      expect(d.outlet(a.outletId)!.lean, l);
    }
  });

  test('a lone side with pictures gives fewer than two picks', () {
    final Digest d = Digest.fromJson(withImages(<String>{'right'}));
    expect(SidePictures.pick(d.stories.first, d), hasLength(1));
  });

  testWidgets('the front page shows the side strip on the lead story; '
      'failed loads fall back to initials without errors',
      (WidgetTester tester) async {
    await pumpSidesApp(tester, harness: harnessFor(withImages(null)));
    expect(find.byKey(SidePictures.stripKey), findsOneWidget);
    expect(find.byType(ArticleThumb), findsNWidgets(3));
    expect(
      find.descendant(of: find.byType(ArticleThumb), matching: find.byType(OutletAvatar)),
      findsNWidgets(3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('one side with pictures: no strip at all (no lone photo)',
      (WidgetTester tester) async {
    await pumpSidesApp(tester, harness: harnessFor(withImages(<String>{'right'})));
    expect(find.byKey(SidePictures.stripKey), findsNothing);
  });

  testWidgets('the story page shows the strip and a thumbnail on each quote',
      (WidgetTester tester) async {
    final Map<String, Object?> j = withImages(null);
    final String id =
        ((j['stories']! as List<Object?>).first! as Map<String, Object?>)['id']! as String;
    await pumpSidesApp(tester, harness: harnessFor(j), initialLocation: '/story/$id');
    expect(find.byKey(SidePictures.stripKey), findsOneWidget);
    expect(find.byType(ArticleThumb), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
