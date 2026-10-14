import 'dart:convert';
import 'dart:io';

import 'package:sides/features/digest/domain/digest.dart';

/// The fixture IS the bundled sample: the real 14 Oct 2026 pipeline digest
/// (`pipeline/out/digest.json` copied to `assets/sample_digest.json`).
/// Read synchronously: awaiting file IO inside testWidgets can hang.
const String sampleDigestPath = 'assets/sample_digest.json';

String sampleDigestBody() => File(sampleDigestPath).readAsStringSync();

Map<String, Object?> sampleDigestJson() =>
    jsonDecode(sampleDigestBody()) as Map<String, Object?>;

Digest sampleDigest() => Digest.fromJson(sampleDigestJson());

/// The sample's own instant, used as "now" so the cache reads as fresh.
final DateTime sampleNow = DateTime.utc(2026, 10, 14, 23, 0);
