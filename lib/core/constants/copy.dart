import '../../features/digest/domain/digest.dart';
import '../config/app_config.dart';

/// Every fixed UI string about the news content, in one place so the
/// neutrality rule can be reviewed in a single file: the app describes what
/// coverage contains and never judges an outlet.
abstract final class Copy {
  static String blindspotLean(Lean l) => switch (l) {
        Lean.left => 'Only left-leaning outlets covered this',
        Lean.centre => 'Only centre outlets covered this',
        Lean.right => 'Only right-leaning outlets covered this',
      };

  static String blindspotBloc(Bloc b) =>
      'Only ${b.adjective} outlets covered this';

  static String leanGroup(Lean l) => switch (l) {
        Lean.left => 'Left-leaning outlets',
        Lean.centre => 'Centre outlets',
        Lean.right => 'Right-leaning outlets',
      };

  static String blocGroup(Bloc b) => '${b.adjective} outlets';

  static String omissionHeading(Lean l) => switch (l) {
        Lean.left => 'Not in left-leaning coverage',
        Lean.centre => 'Not in centre coverage',
        Lean.right => 'Not in right-leaning coverage',
      };

  /// Detail app-bar title: a rank is a position, not a name.
  static String storyPosition(int rank, int total) => '$rank of $total';
  static String storyPositionSpoken(int rank, int total) =>
      'Story $rank of $total';

  static String outletCount(int n) => n == 1 ? '1 outlet' : '$n outlets';

  static String unratedNote(int n) => n == 1
      ? '1 outlet has no political-lean rating, so it counts only in West / East.'
      : '$n outlets have no political-lean rating, so they count only in West / East.';

  static const String axisLean = 'Political lean';
  static const String axisBloc = 'West / East';
  static const String headlineWording = 'Headline wording';
  static const String emphasis = 'What they emphasise';
  static const String agreed = 'What all sources agree on';
  static const String omissions = 'What each side leaves out';
  static const String contested = 'Contested claims';
  static const String opinion = 'Opinion & analysis';
  static const String opinionNote =
      'Commentary and analysis pieces, kept apart from the reporting above.';
  static const String contradictions = 'East–West contradictions';
  static const String noContradictions =
      'No contradictions found in today\'s coverage';
  static const String noneFound = 'None found in today\'s coverage.';
  static const String analysisUnavailableTitle = 'Analysis';
  static const String analysisUnavailable =
      'Analysis isn\'t available for this story today. '
      'Its sources are listed below.';
  static const String assertedBy = 'Stated by';
  static const String disputedBy = 'Disputed by';
  static const String sources = 'Sources';
  static const String noLeanRating = 'No lean rating';

  static const String howItWorks =
      'Once a day Sides collects headlines and short summaries from news '
      'outlets across the political spectrum and from Western and Eastern '
      'countries, groups them into the day\'s top stories, and compares how '
      'each side frames them.\n\n'
      'The comparison is generated automatically by an AI model from '
      'headlines and short summaries only, once a day, and is not reviewed by '
      'a human editor. Every point links to its source, so you can read '
      'the original article on the outlet\'s own site. Points that cannot be '
      'traced to a source are left out.';

  /// Settings › How it works and the story page: report a wrong or
  /// offensive story (compliance m2, AI-generated content reporting).
  static const String reportStory = 'Report a problem with a story';
  static const String reportThisStory = 'Report a problem with this story';
  static const String reportStorySubtitle =
      'Tell us if a summary is wrong, misleading or offensive';
  static const String reportStorySubject = 'Sides story report';
  static String reportStoryBody({String? title, String? date}) => <String>[
        if (title != null) 'Story: $title',
        if (date != null) 'Digest date: $date',
        if (title != null || date != null) '',
        'What is wrong with it:',
        '',
      ].join('\n');

  static const String ratingBasis =
      'Political-lean labels come from published media-bias ratings '
      '(listed for each outlet below). Outlets without a rating, such as '
      'state media, appear only in the West / East comparison.';

  /// Settings › About: publisher and contact (Play News apps policy).
  static const String publishedBy = 'Published by Froggy Eye Ltd';
  static const String contact = 'Contact';
  static const String privacyPolicy = 'Privacy policy';
  static const String contactFailed =
      'No mail app found. Email us at ${AppConfig.contactEmail}.';
}
