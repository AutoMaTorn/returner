import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_paths.dart';
import '../core/binaries.dart';
import '../core/process_runner.dart';
import '../services/database.dart';
import '../services/device_service.dart';
import '../services/download_service.dart';
import '../services/ipa_inspector.dart';
import '../services/ipatool_service.dart';
import '../services/operation_journal.dart';
import '../services/package_store.dart';
import '../services/secure_store.dart';

/// Resolved before the app starts; overridden in `main`.
final appPathsProvider = Provider<AppPaths>(
  (ref) => throw UnimplementedError('appPathsProvider must be overridden'),
);

final processRunnerProvider = Provider<ProcessRunner>(
  (ref) => const SystemProcessRunner(),
);

final binariesProvider = Provider<Binaries>(
  (ref) => Binaries.forCurrentProcess(),
);

final secureStoreProvider = Provider<SecureStore>(
  (ref) => SecureStore(const PlatformSecretsBackend()),
);

final ipatoolServiceProvider = Provider<IpatoolService>((ref) {
  final binaries = ref.watch(binariesProvider);
  return IpatoolService(
    runner: ref.watch(processRunnerProvider),
    executable: () => binaries.ipatool,
    stateDirectory: ref.watch(appPathsProvider).ipatoolState,
    secureStore: ref.watch(secureStoreProvider),
  );
});

final deviceServiceProvider = Provider<DeviceService>((ref) {
  final binaries = ref.watch(binariesProvider);
  return DeviceService(
    runner: ref.watch(processRunnerProvider),
    executable: () => binaries.ios,
  );
});

final downloadServiceProvider = Provider<DownloadService>(
  (ref) => DownloadService(ref.watch(ipatoolServiceProvider)),
);

final ipaInspectorProvider = Provider<IpaInspector>(
  (ref) => const IpaInspector(),
);

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase.open(ref.watch(appPathsProvider).database);
  ref.onDispose(database.close);
  return database;
});

final operationJournalProvider = Provider<OperationJournal>(
  (ref) => OperationJournal(ref.watch(databaseProvider)),
);

final packageStoreProvider = Provider<PackageStore>(
  (ref) => PackageStore(
    ref.watch(databaseProvider),
    ref.watch(appPathsProvider).library,
  ),
);
