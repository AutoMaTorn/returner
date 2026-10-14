/// Identifies what to fetch from the App Store. All ids are strings.
///
/// [appStoreId] is preferred: it works for apps whose store page is gone.
class AppRef {
  const AppRef({this.appStoreId, this.bundleId, this.externalVersionId})
    : assert(appStoreId != null || bundleId != null);

  /// Numeric id of a store listing ("adamId").
  final String? appStoreId;
  final String? bundleId;

  /// Apple's id of one build; not a display version like "3.2.1".
  final String? externalVersionId;

  /// Stable key for file names and logs.
  String get key => appStoreId ?? bundleId!;

  AppRef withVersion(String? externalVersionId) => AppRef(
    appStoreId: appStoreId,
    bundleId: bundleId,
    externalVersionId: externalVersionId,
  );

  static final _storeUrlId = RegExp(r'/id(\d+)(?:[/?#]|$)');
  static final _digits = RegExp(r'^\d+$');
  static final _bundleId = RegExp(r'^[A-Za-z0-9-]+(\.[A-Za-z0-9_-]+)+$');

  /// Parses user input: a numeric App Store ID, an `apps.apple.com` link
  /// (only `id<digits>` matters) or a bundle id. Returns null if none fits.
  static AppRef? parse(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;
    if (_digits.hasMatch(value)) return AppRef(appStoreId: value);

    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) {
      final host = uri.host.toLowerCase();
      if ((uri.scheme == 'https' || uri.scheme == 'http') &&
          (host == 'apps.apple.com' || host == 'itunes.apple.com')) {
        final match = _storeUrlId.firstMatch(uri.path);
        if (match != null) return AppRef(appStoreId: match[1]);
      }
      return null;
    }
    if (_bundleId.hasMatch(value)) return AppRef(bundleId: value);
    return null;
  }

  @override
  String toString() =>
      'AppRef($key${externalVersionId == null ? '' : '@$externalVersionId'})';
}
