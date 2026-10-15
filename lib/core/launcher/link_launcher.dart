import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens original articles and policy pages in the external browser, and
/// the publisher contact address in the mail app.
/// The app never renders article pages itself.
abstract class LinkLauncher {
  /// Opens an http/https [uri]. Returns false when nothing could open it.
  /// Article links arrive from the digest, so no other scheme is accepted.
  Future<bool> open(Uri uri);

  /// Opens a `mailto:` [uri] in the mail app. Returns false for any other
  /// scheme or when no mail app is available. Kept separate from [open] so
  /// the article path never gains the mailto scheme.
  Future<bool> compose(Uri mailto);
}

typedef LaunchFn = Future<bool> Function(Uri uri);

Future<bool> _launchExternal(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

class ExternalBrowserLauncher implements LinkLauncher {
  /// [launch] is a test seam; production always uses url_launcher.
  const ExternalBrowserLauncher({this.launch = _launchExternal});

  final LaunchFn launch;

  @override
  Future<bool> open(Uri uri) async {
    if (uri.scheme != 'https' && uri.scheme != 'http') return false;
    try {
      return await launch(uri);
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> compose(Uri mailto) async {
    if (mailto.scheme != 'mailto') return false;
    try {
      return await launch(mailto);
    } on Object {
      return false;
    }
  }
}

final Provider<LinkLauncher> linkLauncherProvider =
    Provider<LinkLauncher>((Ref ref) => const ExternalBrowserLauncher());
