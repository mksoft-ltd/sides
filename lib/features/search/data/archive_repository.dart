// ignore_for_file: prefer_initializing_formals
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../digest/data/digest_repository.dart';
import '../../digest/domain/digest.dart';

/// One row of `digest/index.json` on the site.
@immutable
class ArchiveEntry {
  const ArchiveEntry({required this.date, required this.stories});
  final String date;
  final int stories;
}

/// Past digests from the site's archive, cached on the device so a search
/// repeats offline and never downloads a day twice.
abstract class ArchiveRepository {
  /// Newest first. With [online] false only what is saved on the phone is
  /// read (instant, no network). Empty when nothing is available.
  Future<List<ArchiveEntry>> index({bool online = true});

  /// The digest for [date], or null when it is not available. With [online]
  /// false only a copy saved on the phone is returned.
  Future<Digest?> digest(String date, {bool online = true});
}

class NetworkArchiveRepository implements ArchiveRepository {
  NetworkArchiveRepository({
    required http.Client client,
    Directory? cacheDir,
    DigestParser parse = NetworkDigestRepository.defaultParser,
    this.timeout = AppConfig.fetchTimeout,
  })  : _client = client,
        _dir = cacheDir,
        _parse = parse;

  final http.Client _client;
  final Directory? _dir;
  final DigestParser _parse;
  final Duration timeout;
  final Map<String, Digest> _memory = <String, Digest>{};

  File? _file(String name) =>
      _dir == null ? null : File('${_dir.path}/$name');

  Future<String?> _get(Uri url) async {
    try {
      final http.Response r = await _client
          .get(url, headers: const <String, String>{'Accept': 'application/json'})
          .timeout(timeout);
      if (r.statusCode != 200) return null;
      return utf8.decode(r.bodyBytes);
    } on Object catch (e) {
      debugPrint('Archive fetch failed: $e');
      return null;
    }
  }

  @override
  Future<List<ArchiveEntry>> index({bool online = true}) async {
    final File? cached = _file('index.json');
    String? body = online ? await _get(Uri.parse(AppConfig.archiveIndexUrl)) : null;
    if (body != null) {
      await _save(cached, body);
    } else if (cached != null && await cached.exists()) {
      body = await cached.readAsString();
    }
    if (body == null) return const <ArchiveEntry>[];
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is! List<Object?>) return const <ArchiveEntry>[];
      return <ArchiveEntry>[
        for (final Object? e in decoded)
          if (e is Map<String, Object?> &&
              e['date'] is String &&
              e['stories'] is int)
            ArchiveEntry(date: e['date']! as String, stories: e['stories']! as int),
      ];
    } on FormatException {
      return const <ArchiveEntry>[];
    }
  }

  @override
  Future<Digest?> digest(String date, {bool online = true}) async {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) return null;
    final Digest? inMemory = _memory[date];
    if (inMemory != null) return inMemory;
    final File? cached = _file('$date.json');
    String? body;
    if (cached != null && await cached.exists()) {
      body = await cached.readAsString();
    } else if (online) {
      body = await _get(Uri.parse(AppConfig.archiveDigestUrl(date)));
      if (body != null) await _save(cached, body);
    }
    if (body == null) return null;
    final Digest? digest = (await _parse(body)).digest;
    if (digest != null) _memory[date] = digest;
    return digest;
  }

  Future<void> _save(File? f, String body) async {
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      await f.writeAsString(body, flush: true);
    } on Object catch (e) {
      debugPrint('Archive cache not saved: $e');
    }
  }
}
