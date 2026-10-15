import '../../features/digest/domain/digest.dart';

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
  static const String assertedBy = 'Stated by';
  static const String disputedBy = 'Disputed by';
  static const String sources = 'Sources';
  static const String noLeanRating = 'No lean rating';

  static const String howItWorks =
      'Once a day Sides collects headlines and short summaries from news '
      'outlets across the political spectrum and from Western and Eastern '
      'countries, groups them into the day\'s top stories, and compares how '
      'each side frames them.\n\n'
      'The comparison is based on headlines and short summaries only, '
      'generated once a day. Every point links to its source, so you can read '
      'the original article on the outlet\'s own site. Points that cannot be '
      'traced to a source are left out.';

  static const String ratingBasis =
      'Political-lean labels come from published media-bias ratings '
      '(listed for each outlet below). Outlets without a rating, such as '
      'state media, appear only in the West / East comparison.';
}
