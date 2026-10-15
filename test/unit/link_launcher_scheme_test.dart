import 'package:flutter_test/flutter_test.dart';
import 'package:sides/core/config/app_config.dart';
import 'package:sides/core/launcher/link_launcher.dart';

/// The article path and the mail path each accept only their own schemes.
/// The launch function always succeeds here, so a refusal can only come from
/// the scheme guard.
void main() {
  late List<Uri> launched;
  late ExternalBrowserLauncher launcher;

  setUp(() {
    launched = <Uri>[];
    launcher = ExternalBrowserLauncher(launch: (Uri u) async {
      launched.add(u);
      return true;
    });
  });

  test('open accepts http and https', () async {
    expect(await launcher.open(Uri.parse(AppConfig.privacyPolicyUrl)), isTrue);
    expect(await launcher.open(Uri.parse('http://example.com/a')), isTrue);
    expect(launched, hasLength(2));
  });

  test('open refuses mailto and other non-web schemes', () async {
    expect(await launcher.open(AppConfig.contactMailto), isFalse);
    expect(await launcher.open(Uri.parse('javascript:alert(1)')), isFalse);
    expect(await launcher.open(Uri.parse('file:///etc/hosts')), isFalse);
    expect(launched, isEmpty);
  });

  test('compose accepts the contact mailto', () async {
    expect(await launcher.compose(AppConfig.contactMailto), isTrue);
    expect(launched.single.toString(), 'mailto:info@froggyeye.com');
  });

  test('compose refuses anything but mailto', () async {
    expect(await launcher.compose(Uri.parse(AppConfig.privacyPolicyUrl)),
        isFalse);
    expect(await launcher.compose(Uri.parse('tel:+441234567890')), isFalse);
    expect(await launcher.compose(Uri.parse('javascript:alert(1)')), isFalse);
    expect(launched, isEmpty);
  });

  test('a throwing launch reports false', () async {
    final ExternalBrowserLauncher l =
        ExternalBrowserLauncher(launch: (Uri u) async => throw StateError('x'));
    expect(await l.open(Uri.parse(AppConfig.privacyPolicyUrl)), isFalse);
    expect(await l.compose(AppConfig.contactMailto), isFalse);
  });
}
