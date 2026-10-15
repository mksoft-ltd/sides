import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sides/core/constants/copy.dart';
import 'package:sides/features/digest/domain/digest.dart';
import 'package:sides/features/story/presentation/widgets/story_detail_view.dart';
import 'package:sides/shared/widgets/report_story_tile.dart';

import '../fixtures/fixtures.dart';
import '../helpers/pump_app.dart';

/// Compliance m2: the app says the analysis is AI-generated, and a reader
/// can report a story by mail (Play AI-generated content, Apple 2.3.1).
void main() {
  const Size tall = Size(390, 3000);
  const String subject = 'subject=Sides%20story%20report';

  testWidgets('How it works says an AI model writes the analysis', (
    WidgetTester tester,
  ) async {
    await pumpSidesApp(tester, initialLocation: '/settings', size: tall);
    expect(find.text(Copy.howItWorks), findsOneWidget);
    expect(Copy.howItWorks, contains('generated automatically by an AI model'));
    expect(Copy.howItWorks, contains('headlines and short summaries'));
  });

  testWidgets('Settings report tile composes a mailto with the subject only', (
    WidgetTester tester,
  ) async {
    final TestHarness h = await pumpSidesApp(
      tester,
      initialLocation: '/settings',
      size: tall,
    );
    await tester.tap(find.text(Copy.reportStory));
    await tester.pumpAndSettle();

    final Uri mail = h.launcher.composed.single;
    expect(mail.scheme, 'mailto');
    expect(mail.path, 'info@froggyeye.com');
    expect(mail.toString(), contains(subject));
    expect(mail.toString(), isNot(contains('Story%3A')));
    expect(
      h.launcher.opened,
      isEmpty,
      reason: 'mail must not go through the http/https article path',
    );
  });

  testWidgets('story page report carries the story title and digest date', (
    WidgetTester tester,
  ) async {
    final Digest d = sampleDigest();
    final Story s = d.stories.first;
    final TestHarness h = await pumpSidesApp(
      tester,
      initialLocation: '/story/${s.id}',
    );
    final Finder tile = find.byKey(ReportStoryTile.tileKey);
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find
          .descendant(
            of: find.byType(StoryDetailView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text(Copy.reportThisStory), findsOneWidget);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    final Uri mail = h.launcher.composed.single;
    expect(mail.toString(), contains(subject));
    final String body = Uri.decodeComponent(
      mail.query
          .split('&')
          .firstWhere((String p) => p.startsWith('body='))
          .substring(5),
    );
    expect(body, contains('Story: ${s.title}'));
    expect(body, contains('Digest date: ${d.date}'));
    expect(h.launcher.opened, isEmpty);
  });

  testWidgets('a failed report launch shows the address', (
    WidgetTester tester,
  ) async {
    final TestHarness h = TestHarness()..launcher.result = false;
    await pumpSidesApp(
      tester,
      harness: h,
      initialLocation: '/settings',
      size: tall,
    );
    await tester.tap(find.text(Copy.reportStory));
    await tester.pumpAndSettle();
    expect(find.text(Copy.contactFailed), findsOneWidget);
  });

  test('the report mailto is percent-encoded, never "+" for spaces', () {
    final Uri u = storyReportMailto(title: 'A & B = C?', date: '2026-10-15');
    expect(u.toString(), isNot(contains('+')));
    final String body = Uri.decodeComponent(u.query.split('body=').last);
    expect(body, contains('Story: A & B = C?'));
    expect(
      u.query.split('&'),
      hasLength(2),
      reason: 'an "&" in the title must not split the query',
    );
  });
}
