/// Facts read from a downloaded `.ipa`.
class IpaInfo {
  const IpaInfo({
    required this.bundleId,
    required this.displayName,
    required this.sha256,
    required this.size,
    this.displayVersion,
    this.bundleVersion,
    this.minimumOS,
  });

  final String bundleId;

  /// The name shown under the icon on the device.
  final String displayName;
  final String? displayVersion;
  final String? bundleVersion;
  final String? minimumOS;

  /// SHA-256 of the whole file, lowercase hex.
  final String sha256;
  final int size;
}

/// Compares dotted versions by numeric segments ("17.10" > "17.9").
/// Missing segments count as zero; non-numeric segments compare as zero.
int compareVersions(String a, String b) {
  final left = a.split('.');
  final right = b.split('.');
  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final l = i < left.length ? int.tryParse(left[i]) ?? 0 : 0;
    final r = i < right.length ? int.tryParse(right[i]) ?? 0 : 0;
    if (l != r) return l.compareTo(r);
  }
  return 0;
}
