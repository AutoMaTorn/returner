/// Data returned by the App Store through ipatool.
library;

class AccountInfo {
  const AccountInfo({required this.email, required this.name});

  final String email;
  final String name;
}

/// An app from search or from the purchase history.
class StoreApp {
  const StoreApp({
    required this.appStoreId,
    required this.bundleId,
    required this.name,
    this.version,
    this.price,
    this.purchaseDate,
    this.platforms = const [],
  });

  final String appStoreId;
  final String bundleId;
  final String name;
  final String? version;
  final num? price;
  final DateTime? purchaseDate;
  final List<String> platforms;
}

class PurchasePage {
  const PurchasePage({
    required this.apps,
    required this.page,
    required this.totalCount,
  });

  final List<StoreApp> apps;
  final int page;

  /// Number of owned apps reported by Apple, across all pages.
  final int totalCount;
}

class VersionMetadata {
  const VersionMetadata({
    required this.externalVersionId,
    required this.displayVersion,
    this.releaseDate,
  });

  final String externalVersionId;
  final String displayVersion;
  final DateTime? releaseDate;
}

/// Result of a finished ipatool download.
class DownloadResult {
  const DownloadResult({required this.path, required this.licenseAcquired});

  final String path;

  /// True if this call obtained the license (`--purchase`).
  final bool licenseAcquired;
}
