/// Typography for quoting a headline or snippet inside curly double quotes.
abstract final class Quotes {
  static final RegExp _opensAfter = RegExp(r'[\s(\[{—–-]');

  /// Wraps [text] in “ ” and folds any double quotes inside it, straight or
  /// curly, to single curly quotes, so a quote within a quote reads
  /// “identified at a ‘very early stage.’” rather than doubling up.
  ///
  /// A mark opens (‘) at the start or after whitespace or an opening
  /// bracket or dash, and closes (’) anywhere else.
  static String wrap(String text) {
    final StringBuffer out = StringBuffer('“');
    for (int i = 0; i < text.length; i++) {
      final String ch = text[i];
      if (ch == '"') {
        final bool opens = i == 0 || _opensAfter.hasMatch(text[i - 1]);
        out.write(opens ? '‘' : '’');
      } else if (ch == '“') {
        out.write('‘');
      } else if (ch == '”') {
        out.write('’');
      } else {
        out.write(ch);
      }
    }
    out.write('”');
    return out.toString();
  }
}
