import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A newer published release of Returner.
class AvailableUpdate {
  const AvailableUpdate({required this.version, required this.pageUrl});

  /// Like `0.2.3`.
  final String version;

  /// The release page on GitHub, where the user downloads it.
  final String pageUrl;
}

/// Asks GitHub for the latest published release of Returner. Notification
/// only: nothing is downloaded or installed. The request carries no account
/// data: a fixed client name and the app version.
class UpdateService {
  UpdateService({
    required this._client,
    required this.currentVersion,
    this.timeout = const Duration(seconds: 15),
  });

  static const repository = 'AutoMaTorn/returner';
  static final _latest = Uri.https(
    'api.github.com',
    '/repos/$repository/releases/latest',
  );

  /// Release pages are only ever opened from here.
  static const _pagePrefix = 'https://github.com/$repository/releases/';

  final http.Client _client;
  final String currentVersion;
  final Duration timeout;

  /// The newer release, or null when this version is the latest.
  /// Throws [UpdateCheckFailed] when GitHub could not be asked.
  Future<AvailableUpdate?> check() async {
    final http.Response response;
    try {
      response = await _client
          .get(
            _latest,
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'Returner/$currentVersion',
            },
          )
          .timeout(timeout);
    } on Exception {
      throw const UpdateCheckFailed();
    }
    // No published release yet.
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw const UpdateCheckFailed();

    final Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const UpdateCheckFailed();
    }
    if (body is! Map) throw const UpdateCheckFailed();
    final tag = body['tag_name'];
    final page = body['html_url'];
    final latest = tag is String ? parseVersion(tag) : null;
    final current = parseVersion(currentVersion);
    if (latest == null || current == null) throw const UpdateCheckFailed();
    if (body['draft'] == true || body['prerelease'] == true) return null;
    if (compareVersions(latest, current) <= 0) return null;
    return AvailableUpdate(
      version: latest.join('.'),
      pageUrl: page is String && page.startsWith(_pagePrefix)
          ? page
          : 'https://github.com/$repository/releases/latest',
    );
  }
}

class UpdateCheckFailed implements Exception {
  const UpdateCheckFailed();
}

/// `v0.2.3` or `0.2.3` → [0, 2, 3]; anything else → null.
List<int>? parseVersion(String text) {
  final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(text.trim());
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}

int compareVersions(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return 0;
}
