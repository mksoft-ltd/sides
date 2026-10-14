import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens original articles and policy pages in the external browser.
/// The app never renders article pages itself.
abstract class LinkLauncher {
  /// Returns false when nothing could open [uri].
  Future<bool> open(Uri uri);
}

class ExternalBrowserLauncher implements LinkLauncher {
  const ExternalBrowserLauncher();

  @override
  Future<bool> open(Uri uri) async {
    if (uri.scheme != 'https' && uri.scheme != 'http') return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}

final Provider<LinkLauncher> linkLauncherProvider =
    Provider<LinkLauncher>((Ref ref) => const ExternalBrowserLauncher());
