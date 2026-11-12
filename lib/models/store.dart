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

/// A component ipatool downloads before its first sign-in on a computer.
enum ComponentStage {
  /// The Unicorn emulator library (GitHub on Windows, PyPI on macOS).
  runtime('runtime'),

  /// Frameworks taken from Apple's macOS restore image.
  appleAssets('apple-assets');

  const ComponentStage(this.wireName);

  /// The `stage` value in `ipatool prepare` output.
  final String wireName;

  static ComponentStage? fromName(String name) {
    for (final stage in values) {
      if (stage.wireName == name) return stage;
    }
    return null;
  }
}

/// One `ipatool prepare` report: the component now downloading and how many
/// bytes of the whole run have arrived out of about [total].
class ComponentsProgress {
  const ComponentsProgress(this.stage, {this.bytes = 0, this.total = 0});

  final ComponentStage stage;
  final int bytes;

  /// Zero when ipatool does not know the size.
  final int total;
}
