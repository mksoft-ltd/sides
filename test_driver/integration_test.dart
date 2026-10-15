import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Writes each capture from `integration_test/screenshots_test.dart` to
/// `$SCREENSHOT_DIR/<name>.png` (default `store_assets/screenshots/raw`).
///
/// Set SCREENSHOT_DIR per device (e.g. `.../raw/iphone_69`, `.../raw/ipad_13`)
/// so a second device run does not overwrite the first. After every run,
/// check the captures differ: on some iOS simulator builds every
/// `takeScreenshot` is the launch screen while the harness stays green.
///
///   md5 "$SCREENSHOT_DIR"/*.png | sort -k4 | uniq -c -f3
Future<void> main() async {
  final String dir =
      Platform.environment['SCREENSHOT_DIR'] ?? 'store_assets/screenshots/raw';

  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          try {
            await Directory(dir).create(recursive: true);
            await File('$dir/$name.png').writeAsBytes(bytes, flush: true);
            return true;
          } on Object catch (e) {
            // Returning false fails the drive. Swallowing it would let a full disk
            // or a read-only path produce a green run with missing captures.
            stderr.writeln('Could not write screenshot "$name" to $dir: $e');
            return false;
          }
        },
  );
}
