class Device {
  const Device({
    required this.udid,
    required this.name,
    required this.productType,
    required this.osVersion,
  });

  final String udid;

  /// User-visible device name; falls back to "iPhone" when unknown.
  final String name;

  /// Hardware identifier such as `iPhone17,1`.
  final String productType;
  final String osVersion;

  @override
  bool operator ==(Object other) =>
      other is Device &&
      other.udid == udid &&
      other.name == name &&
      other.productType == productType &&
      other.osVersion == osVersion;

  @override
  int get hashCode => Object.hash(udid, name, productType, osVersion);
}

/// An app found in the device's installed list.
class InstalledApp {
  const InstalledApp({
    required this.bundleId,
    required this.name,
    required this.version,
  });

  final String bundleId;
  final String name;
  final String version;
}

/// Progress of `ios install`.
class InstallProgress {
  const InstallProgress(this.percent, this.status);

  /// Null while the file is being transferred and go-ios reports nothing.
  final int? percent;
  final String? status;
}
