import 'package:flutter_test/flutter_test.dart';
import 'package:sides/core/text/quotes.dart';

void main() {
  group('Quotes.wrap', () {
    test('plain text gets curly double quotes', () {
      expect(Quotes.wrap('no quotes here'), '“no quotes here”');
    });

    test('inner straight double quotes become single curly quotes', () {
      // Fox News, story 1 of the sample digest.
      expect(
        Quotes.wrap('identified at a "very early stage."'),
        '“identified at a ‘very early stage.’”',
      );
    });

    test('a quote that is itself wholly quoted', () {
      expect(
        Quotes.wrap('"is a betrayal of the people of Ukraine"'),
        '“‘is a betrayal of the people of Ukraine’”',
      );
    });

    test('inner curly double quotes fold too', () {
      expect(Quotes.wrap('the “red line” was'), '“the ‘red line’ was”');
    });

    test('opening marks after a bracket or dash, apostrophes untouched', () {
      expect(
        Quotes.wrap('PM\'s plan (" a reset") —"now"'),
        '“PM\'s plan (‘ a reset’) —‘now’”',
      );
    });
  });
}
