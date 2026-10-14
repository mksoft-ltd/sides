import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The last good digest exactly as downloaded, plus how it was fetched.
@immutable
class CachedDigest {
  const CachedDigest({
    required this.body,
    required this.fetchedAt,
    this.etag,
  });

  /// Raw JSON as served. Stored verbatim so the parser is the single
  /// authority on what the file means.
  final String body;
  final DateTime fetchedAt;
  final String? etag;

  CachedDigest copyWith({DateTime? fetchedAt, String? etag}) => CachedDigest(
        body: body,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        etag: etag ?? this.etag,
      );
}

/// Where the last digest lives between launches. A seam so widget tests use
/// memory and never touch path_provider.
abstract class DigestCache {
  Future<CachedDigest?> read();
  Future<void> write(CachedDigest value);

  /// Updates only the metadata (after a 304 Not Modified).
  Future<void> touch({required DateTime fetchedAt, String? etag});
}

class InMemoryDigestCache implements DigestCache {
  InMemoryDigestCache([this.value]);
  CachedDigest? value;
  int writes = 0;

  @override
  Future<CachedDigest?> read() async => value;

  @override
  Future<void> write(CachedDigest v) async {
    value = v;
    writes++;
  }

  @override
  Future<void> touch({required DateTime fetchedAt, String? etag}) async {
    value = value?.copyWith(fetchedAt: fetchedAt, etag: etag);
  }
}

/// `latest.json` + `latest.meta.json` in the app documents directory.
///
/// Writes go through a uniquely named temp file and a rename, so a phone
/// that dies mid-write keeps the previous digest rather than a torn file.
class FileDigestCache implements DigestCache {
  FileDigestCache(this.directory);

  static Future<FileDigestCache> open() async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${docs.path}/digest');
    return FileDigestCache(dir);
  }

  final Directory directory;
  int _writes = 0;

  File get _body => File('${directory.path}/latest.json');
  File get _meta => File('${directory.path}/latest.meta.json');

  @override
  Future<CachedDigest?> read() async {
    try {
      if (!_body.existsSync() || !_meta.existsSync()) return null;
      final Object? meta = jsonDecode(await _meta.readAsString());
      if (meta is! Map<String, Object?>) return null;
      final DateTime? fetchedAt =
          DateTime.tryParse(meta['fetched_at'] as String? ?? '');
      if (fetchedAt == null) return null;
      return CachedDigest(
        body: await _body.readAsString(),
        fetchedAt: fetchedAt.toUtc(),
        etag: meta['etag'] as String?,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(CachedDigest value) async {
    await directory.create(recursive: true);
    await _atomicWrite(_body, value.body);
    await _writeMeta(value.fetchedAt, value.etag);
  }

  @override
  Future<void> touch({required DateTime fetchedAt, String? etag}) async {
    final CachedDigest? current = await read();
    if (current == null) return;
    await _writeMeta(fetchedAt, etag ?? current.etag);
  }

  Future<void> _writeMeta(DateTime fetchedAt, String? etag) => _atomicWrite(
        _meta,
        jsonEncode(<String, Object?>{
          'fetched_at': fetchedAt.toUtc().toIso8601String(),
          'etag': etag,
        }),
      );

  Future<void> _atomicWrite(File target, String contents) async {
    final File tmp = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}-${_writes++}.tmp',
    );
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(target.path);
  }
}
