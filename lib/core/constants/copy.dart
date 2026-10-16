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
  static const String previousStory = 'Previous story';
  static const String nextStory = 'Next story';

  static String outletCount(int n) => n == 1 ? '1 outlet' : '$n outlets';

  static String unratedNote(int n) => n == 1
      ? '1 outlet has no political-lean rating, so it counts only in West / East.'
      : '$n outlets have no political-lean rating, so they count only in West / East.';

  /// Signal chips on a story card: counts of what the analysis found. They
  /// say where the disagreement is, never who is right.
  static String contestedCount(int n) =>
      n == 1 ? '1 contested claim' : '$n contested claims';
  static String contradictionCount(int n) =>
      n == 1 ? '1 East–West contradiction' : '$n East–West contradictions';
  static const String analysisUnavailableShort = 'Analysis unavailable';
  static const String compare = 'Compare coverage';

  /// Under the date on the digest list.
  static const String digestIntro =
      'How outlets across the political spectrum, and from West and East, '
      'covered today\'s top stories.';

  static const String axisLean = 'Political lean';
  static const String axisBloc = 'West / East';

  /// Section titles. The comparison sections put every side on the page at
  /// once, grouped by what is being compared rather than by side.
  static const String headlines = 'Headlines, side by side';
  static const String emphasis = 'What each side emphasises';
  static const String agreed = 'What all sources agree on';
  static const String omissions = 'What each side leaves out';
  static const String contested = 'Contested claims';
  static const String opinion = 'Opinion & analysis';
  static const String opinionNote =
      'Commentary and analysis pieces, kept apart from the reporting above.';
  static const String contradictions = 'East–West contradictions';
  static const String contradictionsNote =
      'Topics where Western and Eastern outlets state incompatible things.';
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

  /// Jump-bar labels: short, and never the same text as a section title, so
  /// each appears on the page exactly once.
  static const String jumpHeadlines = 'Headlines';
  static const String jumpEmphasis = 'Emphasis';
  static const String jumpAgreed = 'Agreed';
  static const String jumpOmissions = 'Left out';
  static const String jumpContested = 'Contested';
  static const String jumpOpinion = 'Opinion';
  static const String jumpContradictions = 'Contradictions';
  static const String jumpSources = 'Sources';
  static const String onThisPage = 'On this page';

  /// Under a quote: which outlet it is from and whether it is the headline
  /// or the feed summary ("snippet" in the data, "summary" to a reader).
  static String quoteOrigin(String outlet, QuoteField field) =>
      '$outlet · ${field == QuoteField.headline ? 'headline' : 'summary'}';

  static const String sourcesForPoint = 'Sources for this point';
  static String sourcesSheetCount(int n) =>
      n == 1 ? '1 article backs this point' : '$n articles back this point';
  static String moreSources(int n) => '+$n more';

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
