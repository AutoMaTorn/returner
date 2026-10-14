import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../services/driver_service.dart';
import '../core/log.dart';
import '../services/lookup_service.dart';
import '../services/report.dart';
import 'devices.dart';
import 'providers.dart';
import '../core/errors.dart';

/// Small user preferences kept in `settings.json` in the app data folder.
class SettingsFile {
  SettingsFile(this.path);

  final String path;

  Map<String, Object?> read() {
    try {
      final value = jsonDecode(File(path).readAsStringSync());
      if (value is Map<String, dynamic>) return value;
    } on Exception {
      // No settings yet, or an unreadable file: defaults apply.
    }
    return {};
  }

  /// Changes one key and keeps the rest.
  void put(String key, Object? value) {
    try {
      File(path).writeAsStringSync(jsonEncode({...read(), key: value}));
    } on FileSystemException {
      // The choice still holds for this session.
    }
  }
}

final settingsFileProvider = Provider<SettingsFile>(
  (ref) =>
      SettingsFile(p.join(ref.watch(appPathsProvider).root, 'settings.json')),
);

/// "Ночь" (dark) is the primary theme and the default; the user's choice is
/// remembered.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() =>
      ref.watch(settingsFileProvider).read()['theme'] == 'light'
      ? ThemeMode.light
      : ThemeMode.dark;

  void toggle() =>
      set(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);

  void set(ThemeMode mode) {
    state = mode;
    ref
        .read(settingsFileProvider)
        .put('theme', mode == ThemeMode.light ? 'light' : 'dark');
  }
}

/// Storefronts offered for store metadata and icons.
const lookupCountries = ['ru', 'kz', 'by', 'us'];

/// The storefront asked first for names and icons. Downloads do not depend
/// on it: they use the account's own storefront.
final lookupCountryProvider = NotifierProvider<LookupCountryController, String>(
  LookupCountryController.new,
);

class LookupCountryController extends Notifier<String> {
  @override
  String build() {
    final saved = ref.watch(settingsFileProvider).read()['lookupCountry'];
    final country = lookupCountries.contains(saved) ? saved as String : 'ru';
    ref.read(lookupServiceProvider).preferCountry(country);
    return country;
  }

  void set(String country) {
    if (!lookupCountries.contains(country)) return;
    state = country;
    ref.read(settingsFileProvider).put('lookupCountry', country);
    ref.read(lookupServiceProvider).preferCountry(country);
    ref.invalidate(appIconProvider);
  }
}

final driverServiceProvider = Provider<DriverService>(
  (ref) => DriverService(runner: ref.watch(processRunnerProvider)),
);

/// Whether the device list currently fails because Apple's driver is absent.
final driverMissingProvider = Provider<bool>((ref) {
  final devices = ref.watch(devicesProvider);
  return devices.hasError && devices.error is DriverMissing;
});

enum DriverInstallStatus { idle, installing, failed }

class DriverInstallState {
  const DriverInstallState(this.status, [this.message]);

  final DriverInstallStatus status;

  /// Latest line from the installer.
  final String? message;
}

final driverInstallProvider =
    NotifierProvider<DriverInstallController, DriverInstallState>(
      DriverInstallController.new,
    );

class DriverInstallController extends Notifier<DriverInstallState> {
  @override
  DriverInstallState build() =>
      const DriverInstallState(DriverInstallStatus.idle);

  /// Started only by an explicit click.
  Future<void> install() async {
    if (state.status == DriverInstallStatus.installing) return;
    state = const DriverInstallState(DriverInstallStatus.installing);
    final result = await ref
        .read(driverServiceProvider)
        .install(
          onOutput: (line) =>
              state = DriverInstallState(DriverInstallStatus.installing, line),
        );
    state = DriverInstallState(
      result == DriverInstallResult.installed
          ? DriverInstallStatus.idle
          : DriverInstallStatus.failed,
    );
    // The device poll picks the new driver up on its next round.
    ref.invalidate(devicesProvider);
  }
}

final lookupServiceProvider = Provider<LookupService>(
  (ref) => throw UnimplementedError('lookupServiceProvider must be overridden'),
);

/// Local icon file of an app, or null when the store does not know it.
final appIconProvider = FutureProvider.family<File?, String>(
  (ref, appStoreId) => ref.watch(lookupServiceProvider).icon(appStoreId),
);

/// App Store IDs that have an icon bundled with the catalog
/// (`assets/catalog_icons/<id>.png`). Used when neither the store nor a
/// downloaded package has provided one.
final bundledIconsProvider = FutureProvider<Set<String>>((ref) async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  return {
    for (final asset in manifest.listAssets())
      if (asset.startsWith(bundledIconPrefix) && asset.endsWith('.png'))
        asset.substring(bundledIconPrefix.length, asset.length - 4),
  };
});

const bundledIconPrefix = 'assets/catalog_icons/';

const appVersion = '0.1.0';
const ipatoolVersion = '2.7.0-returner.1';
const goIosVersion = '1.3.2';

/// Text for "copy report": version, recent operations and the log tail,
/// with personal data masked.
final reportProvider = Provider<String Function()>((ref) {
  final journal = ref.watch(operationJournalProvider);
  final platform = ref.watch(binariesProvider).platform;
  return () => ReportBuilder(
    appVersion: appVersion,
    platform: platform,
    toolVersions: 'ipatool $ipatoolVersion · go-ios $goIosVersion',
    journal: journal,
    log: Log.file,
  ).build();
});
