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

  /// Search tab.
  static const String tabSearch = 'Search';
  static const String searchTitle = 'Search the news';
  static const String searchIntro =
      'Find a story in today\'s digest and the last two weeks, or have '
      'today\'s coverage of a topic compared.';
  static const String searchHint = 'Topic, place or name';
  static const String searchAction = 'Search';
  static const String searching = 'Searching the archive…';
  static String searchResults(int hits, int days) {
    final String h = hits == 1 ? '1 story' : '$hits stories';
    final String d = days == 1 ? '1 day' : '$days days';
    return '$h across $d';
  }
  static const String archiveUnavailable =
      'The archive could not be reached; only days saved on this device '
      'were searched.';
  static const String today = 'Today\'s digest';
  static const String topicTitle = 'Compare today\'s coverage of this topic';
  static const String topicPitch =
      'Not the story you meant? Sides can compare how outlets covered these '
      'words today, from the headlines it collected this morning.';
  static const String topicPitchNoHits =
      'No digest story matches. Sides can compare how outlets covered these '
      'words today, from the headlines it collected this morning.';
  static const String topicNote =
      'The comparison needs three or more outlets on the topic, takes up to '
      'a minute the first time, and is shared with other readers who search '
      'for the same thing today. The words you typed are sent to our '
      'server; see the privacy policy.';
  static const String topicAction = 'Compare coverage of this topic';
  static const String topicRetry = 'Try again';
  static const String topicWorking =
      'Comparing today\'s coverage… this can take up to a minute.';
  static const String topicReady = 'Ready: here is how the outlets covered it.';
  static const String topicReadyCached =
      'Another reader asked about this today, so it is ready now.';
  static const String topicNoMatch =
      'Fewer than three outlets wrote about those words today, so there is '
      'nothing to compare yet. Try broader words.';
  static const String topicCapped =
      'Today\'s comparison budget is used up. Topics already compared today '
      'still open; new ones return tomorrow.';
  static const String topicRateLimited =
      'That is a lot of new topics in one hour. Please try again later.';
  static const String topicFailed = 'The comparison could not be made.';

  /// Home shell and front page.
  static const String tabToday = 'Today';
  static const String tabBySide = 'By side';
  static const String tabOutlets = 'Outlets';
  static const String leadStory = 'TOP STORY';
  static const String topStories = 'Top stories';
  static const String moreStories = 'More of today\'s stories';
  static const String lensAll = 'All';
  static const String lensContested = 'Contested';
  static const String lensBlindspots = 'Blindspots';
  static const String lensEmpty =
      'No story in today\'s digest matches this filter.';
  static const String bySideTitle = 'Today, side by side';
  static const String bySideIntro =
      'The same stories as each side led with them. Tap a card to compare.';
  static String storyCount(int n) => n == 1 ? '1 story' : '$n stories';

  /// Under the date on the digest list.
  static const String digestIntro =
      'How outlets across the political spectrum, and from West and East, '
      'covered today\'s top stories.';

  /// The "In brief" card at the top of a story: the summary, the conclusion
  /// across the sides, and the list of disagreements. Each part is sourced
  /// like any point; the card says where the sides differ, never who is right.
  static const String inBrief = 'In brief';
  static const String summaryTitle = 'What happened';
  static const String conclusionTitle = 'Across the sides';
  static const String disagreementsTitle = 'Where they disagree';
  static const String noDisagreements =
      'No contested claims or East–West contradictions found in today\'s '
      'coverage.';
  static const String contestedLabel = 'Contested';
  static String agreedCount(int n) => switch (n) {
        0 => 'No agreed points',
        1 => 'Agree on 1 point',
        _ => 'Agree on $n points',
      };
  static const String noContested = 'no contested claims';
  static const String noContradictionsShort = 'no East–West contradictions';
  static String statedByCount(int n) => 'Stated by ${outletCount(n)}';
  static String disputedByCount(int n) => 'Disputed by ${outletCount(n)}';
  static String sourcesLink(int n) => n == 1 ? '1 source' : '$n sources';
  static const String whoCovered = 'Who covered it';
  static const String sidePicturesTitle = 'How each side pictured it';
  static String sidePicturesLabel(List<String> sides) =>
      'Pictures each side used: ${sides.join('; ')}.';
  static const String whoCoveredNote =
      'Tap a side to see its articles.';
  static const String tileAgreed = 'agreed facts';
  static const String tileContested = 'contested claims';
  static const String tileContradictions = 'West–East contradictions';
  static const String contradictionLabel = 'West vs East';

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
