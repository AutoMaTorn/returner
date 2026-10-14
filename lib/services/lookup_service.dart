import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Public store metadata of one app.
class LookupResult {
  const LookupResult({
    required this.appStoreId,
    required this.bundleId,
    required this.name,
    this.artworkUrl,
    this.version,
    this.minimumOS,
  });

  final String appStoreId;
  final String bundleId;
  final String name;
  final String? artworkUrl;
  final String? version;
  final String? minimumOS;
}

/// Optional metadata and icons from the public iTunes Lookup API.
///
/// Everything here is best effort: an app that left the store has no lookup
/// result, and that must never block a download. Failures return null.
class LookupService {
  LookupService({
    required this._client,
    required this.iconDirectory,
    List<String> countries = const ['ru', 'us'],
    this.timeout = const Duration(seconds: 15),
    int maxConcurrent = 4,
  }) : _slots = maxConcurrent,
       _countries = List.of(countries);

  static final _digits = RegExp(r'^\d+$');

  final http.Client _client;

  /// Disk cache for icons.
  final String iconDirectory;

  /// Storefronts tried in order until one knows the app.
  List<String> get countries => List.unmodifiable(_countries);
  List<String> _countries;

  /// Puts [country] first in the search order. Answers cached under the old
  /// order are dropped; icons already on disk stay.
  void preferCountry(String country) {
    final code = country.toLowerCase();
    if (!RegExp(r'^[a-z]{2}$').hasMatch(code)) return;
    if (_countries.isNotEmpty && _countries.first == code) return;
    _countries = [code, ..._countries.where((c) => c != code)];
    _results.clear();
    _icons.clear();
  }

  final Duration timeout;

  final _results = <String, Future<LookupResult?>>{};
  final _icons = <String, Future<File?>>{};
  final _waiting = <Completer<void>>[];
  int _slots;

  /// Store metadata by numeric App Store ID, or null if no storefront has it.
  Future<LookupResult?> lookup(String appStoreId) {
    if (!_digits.hasMatch(appStoreId)) return Future.value();
    return _results[appStoreId] ??= _limited(() => _lookup(appStoreId));
  }

  Future<LookupResult?> _lookup(String appStoreId) async {
    for (final country in _countries) {
      try {
        final response = await _client
            .get(
              Uri.https('itunes.apple.com', '/lookup', {
                'id': appStoreId,
                'country': country,
              }),
            )
            .timeout(timeout);
        if (response.statusCode != 200) continue;
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        final results = body is Map ? body['results'] : null;
        if (results is! List || results.isEmpty) continue;
        final app = results.first;
        if (app is! Map) continue;
        return LookupResult(
          appStoreId: '${app['trackId'] ?? appStoreId}',
          bundleId: '${app['bundleId'] ?? ''}',
          name: '${app['trackName'] ?? ''}',
          artworkUrl: (app['artworkUrl100'] ?? app['artworkUrl512']) as String?,
          version: app['version'] as String?,
          minimumOS: app['minimumOsVersion'] as String?,
        );
      } on Exception {
        // Offline, timeout, malformed answer: try the next storefront.
      }
    }
    return null;
  }

  /// Whether an icon for [appStoreId] is already on disk.
  bool hasIcon(String appStoreId) =>
      _digits.hasMatch(appStoreId) && _iconFile(appStoreId).existsSync();

  /// Stores an icon obtained elsewhere — the artwork inside a downloaded
  /// package — so apps the store no longer lists still get a face.
  Future<File?> saveIcon(String appStoreId, List<int> bytes) async {
    if (!_digits.hasMatch(appStoreId) || bytes.isEmpty) return null;
    final file = _iconFile(appStoreId);
    try {
      await file.parent.create(recursive: true);
      final partial = File('${file.path}.part');
      await partial.writeAsBytes(bytes);
      final saved = await partial.rename(file.path);
      _icons[appStoreId] = Future.value(saved);
      return saved;
    } on FileSystemException {
      return null;
    }
  }

  File _iconFile(String appStoreId) =>
      File(p.join(iconDirectory, '$appStoreId.img'));

  /// The app icon as a local file, downloaded once. Null when unknown.
  Future<File?> icon(String appStoreId) {
    if (!_digits.hasMatch(appStoreId)) return Future.value();
    return _icons[appStoreId] ??= _icon(appStoreId);
  }

  Future<File?> _icon(String appStoreId) async {
    final file = _iconFile(appStoreId);
    if (file.existsSync() && file.lengthSync() > 0) return file;

    final url = (await lookup(appStoreId))?.artworkUrl;
    final uri = url == null ? null : Uri.tryParse(url);
    // Only Apple's image CDN, only over TLS.
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.host.endsWith('.mzstatic.com')) {
      return null;
    }
    return _limited(() async {
      try {
        final response = await _client.get(uri).timeout(timeout);
        if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
          return null;
        }
        await file.parent.create(recursive: true);
        final partial = File('${file.path}.part');
        await partial.writeAsBytes(response.bodyBytes);
        return await partial.rename(file.path);
      } on Exception {
        return null;
      }
    });
  }

  /// Runs [task] with at most `maxConcurrent` requests in flight.
  Future<T> _limited<T>(Future<T> Function() task) async {
    if (_slots == 0) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    } else {
      _slots--;
    }
    try {
      return await task();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete();
      } else {
        _slots++;
      }
    }
  }
}
