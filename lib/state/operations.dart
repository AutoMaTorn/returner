import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cancel.dart';
import '../core/errors.dart';
import '../core/log.dart';
import '../models/app_ref.dart';
import '../models/ipa_info.dart';
import '../services/package_store.dart';
import 'auth.dart';
import 'providers.dart';
import 'settings.dart';

enum OperationStage {
  queued,

  /// Request sent; Apple has not started sending the file yet.
  checkingLicense,
  acquiringLicense,
  downloading,
  validating,
  installing,
  verifying,
  done,
  failed,

  /// The install ended without a definite answer and the device could not
  /// confirm it.
  unknown,
  cancelled;

  bool get isTerminal => index >= done.index;
}

/// What the device said after an install.
enum InstallOutcome {
  /// Bundle id and version are in the device's app list.
  confirmed,

  /// The app is listed but with another (or unreadable) version, so an
  /// upgrade is not proven.
  versionUnknown,

  /// The installer reported success but the app list could not confirm it.
  unverified,
}

class Operation {
  const Operation({
    required this.id,
    required this.app,
    required this.title,
    required this.allowFreeLicense,
    this.deviceUdid,
    this.stage = OperationStage.queued,
    this.bytes = 0,
    this.installPercent,
    this.error,
    this.package,
    this.outcome,
    this.licenseAcquired = false,
    this.installOnly = false,
  });

  final String id;
  final AppRef app;

  /// Name to show: the user's label first, the real app name once known.
  final String title;
  final bool allowFreeLicense;

  /// Device the install is pinned to; null for download-only.
  final String? deviceUdid;
  final OperationStage stage;

  /// Bytes downloaded so far. The total is not known in advance.
  final int bytes;

  /// Null while go-ios transfers the file without reporting progress.
  final int? installPercent;
  final AppError? error;
  final Package? package;
  final InstallOutcome? outcome;
  final bool licenseAcquired;

  /// Installs [package] from the library; nothing is downloaded.
  final bool installOnly;

  Operation copyWith({
    String? title,
    OperationStage? stage,
    int? bytes,
    int? Function()? installPercent,
    AppError? error,
    Package? package,
    InstallOutcome? outcome,
    bool? licenseAcquired,
  }) => Operation(
    id: id,
    app: app,
    allowFreeLicense: allowFreeLicense,
    deviceUdid: deviceUdid,
    title: title ?? this.title,
    stage: stage ?? this.stage,
    bytes: bytes ?? this.bytes,
    installPercent: installPercent == null
        ? this.installPercent
        : installPercent(),
    error: error ?? this.error,
    package: package ?? this.package,
    outcome: outcome ?? this.outcome,
    licenseAcquired: licenseAcquired ?? this.licenseAcquired,
    installOnly: installOnly,
  );
}

final operationsProvider =
    NotifierProvider<OperationsController, List<Operation>>(
      OperationsController.new,
    );

/// Runs download/install operations one at a time and keeps the journal in
/// step with what actually happened.
class OperationsController extends Notifier<List<Operation>> {
  final _tokens = <String, CancelToken>{};
  final _random = Random.secure();
  Future<void> _queue = Future.value();

  @override
  List<Operation> build() => const [];

  /// Cleans up after a previous run: unfinished operations become
  /// "interrupted", their partial files are removed, and library files that
  /// lost their index row are indexed again.
  Future<void> recover() async {
    final journal = ref.read(operationJournalProvider);
    final paths = ref.read(appPathsProvider);
    for (final entry in journal.recoverInterrupted()) {
      await _deleteDirectory(paths.stagingFor(entry.id));
    }
    final store = ref.read(packageStoreProvider);
    final inspector = ref.read(ipaInspectorProvider);
    for (final path in store.unindexedFiles()) {
      try {
        store.adopt(path, await inspector.inspect(path));
      } on AppError {
        Log.warning('Dropping an unreadable library file.');
        await File(path).delete();
      }
    }
    // Packages downloaded before icons were kept.
    for (final package in store.list()) {
      await _keepArtwork(package);
    }
  }

  /// Queues a download of [app], followed by an install when [deviceUdid] is
  /// given. Returns the operation id.
  String start(
    AppRef app, {
    String? title,
    String? deviceUdid,
    bool allowFreeLicense = false,
  }) => _enqueue(
    Operation(
      id: _newId(),
      app: app,
      title: title ?? app.key,
      deviceUdid: deviceUdid,
      allowFreeLicense: allowFreeLicense,
    ),
  );

  /// Queues an install of a package that is already in the library.
  String startInstall(Package package, String deviceUdid) => _enqueue(
    Operation(
      id: _newId(),
      app: AppRef(
        appStoreId: package.appStoreId,
        bundleId: package.info.bundleId,
        externalVersionId: package.requestedVersionId,
      ),
      title: package.info.displayName,
      deviceUdid: deviceUdid,
      allowFreeLicense: false,
      package: package,
      installOnly: true,
    ),
  );

  /// Queues a finished operation again with the same parameters. A package
  /// that already reached the library is installed without a new download.
  ///
  /// [allowFreeLicense] overrides the previous choice: the user agrees to
  /// obtain a free license after seeing that the account has none.
  String? retry(String id, {bool? allowFreeLicense}) {
    final previous = state.where((o) => o.id == id).firstOrNull;
    if (previous == null || !previous.stage.isTerminal) return null;
    final package = previous.package;
    final udid = previous.deviceUdid;
    if (package != null && udid != null && File(package.path).existsSync()) {
      return startInstall(package, udid);
    }
    return start(
      previous.app,
      title: previous.title,
      deviceUdid: udid,
      allowFreeLicense: allowFreeLicense ?? previous.allowFreeLicense,
    );
  }

  String _newId() => [
    for (var i = 0; i < 8; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  String _enqueue(Operation operation) {
    state = [...state, operation];
    _tokens[operation.id] = CancelToken();
    _queue = _queue.then((_) => _run(operation.id));
    return operation.id;
  }

  void cancel(String id) => _tokens[id]?.cancel();

  /// Resolves when everything queued so far has finished.
  Future<void> get idle => _queue;

  Operation _get(String id) => state.firstWhere((o) => o.id == id);

  void _update(String id, Operation Function(Operation) change) {
    state = [
      for (final operation in state)
        if (operation.id == id) change(operation) else operation,
    ];
  }

  void _stage(String id, OperationStage stage, {String? details}) {
    _update(id, (o) => o.copyWith(stage: stage));
    ref
        .read(operationJournalProvider)
        .advance(id, stage.name, details: details);
    Log.info(
      'operation $id: ${stage.name}${details == null ? '' : ' ($details)'}',
    );
  }

  Future<void> _run(String id) async {
    final cancel = _tokens[id]!;
    final journal = ref.read(operationJournalProvider);
    final ipatool = ref.read(ipatoolServiceProvider);
    final staging = ref.read(appPathsProvider).stagingFor(id);
    final operation = _get(id);

    final accountId = ref.read(authProvider).accountId;
    final generation = ipatool.generation;
    journal.begin(
      id: id,
      type: operation.installOnly
          ? 'install'
          : operation.deviceUdid == null
          ? 'download'
          : 'downloadAndInstall',
      accountId: accountId ?? PackageStore.unknownAccount,
      sessionGeneration: generation,
      appKey: operation.app.key,
      deviceUdid: operation.deviceUdid,
      state: OperationStage.queued.name,
    );

    try {
      if (cancel.isCancelled) throw const Cancelled();
      if (operation.installOnly) {
        // A library package carries its license; no session is needed.
        await _install(id, operation.deviceUdid!, operation.package!, cancel);
        return;
      }
      if (accountId == null) throw const AuthSessionExpired();

      final downloaded = await _download(id, staging, cancel);

      _stage(id, OperationStage.validating);
      final info = await ref.read(ipaInspectorProvider).inspect(downloaded);

      // The account changed while we were busy: this package belongs to a
      // session that is gone, so it must not land in the new one's library.
      if (ipatool.generation != generation) throw const Cancelled();
      if (cancel.isCancelled) throw const Cancelled();

      final package = await ref
          .read(packageStoreProvider)
          .add(
            stagedPath: downloaded,
            info: info,
            accountId: accountId,
            app: operation.app,
          );
      _update(id, (o) => o.copyWith(package: package, title: info.displayName));
      await _keepArtwork(package);
      journal.advance(
        id,
        OperationStage.validating.name,
        packageId: package.id,
      );

      final udid = operation.deviceUdid;
      if (udid == null) {
        _stage(id, OperationStage.done);
      } else {
        await _install(id, udid, package, cancel);
      }
    } on Cancelled {
      _stage(id, OperationStage.cancelled);
    } on AppError catch (error) {
      if (error is AuthSessionExpired) {
        ref.read(authProvider.notifier).markExpired();
      }
      _update(id, (o) => o.copyWith(error: error));
      Log.warning(
        'operation $id failed: ${error.code}'
        '${error is Unclassified ? ' ${error.safeDetails}' : ''}',
      );
      journal.advance(
        id,
        OperationStage.failed.name,
        errorCode: error.code,
        details: error is Unclassified ? error.safeDetails : null,
      );
      _update(id, (o) => o.copyWith(stage: OperationStage.failed));
    } catch (error) {
      // A bug, not an Apple or device answer. Never report it as success.
      Log.error('Operation failed unexpectedly', error);
      final wrapped = Unclassified(mask('$error'));
      _update(
        id,
        (o) => o.copyWith(error: wrapped, stage: OperationStage.failed),
      );
      journal.advance(
        id,
        OperationStage.failed.name,
        errorCode: wrapped.code,
        details: wrapped.safeDetails,
      );
    } finally {
      _tokens.remove(id);
      await _deleteDirectory(staging);
    }
  }

  Future<String> _download(
    String id,
    String staging,
    CancelToken cancel,
  ) async {
    final downloads = ref.read(downloadServiceProvider);
    final operation = _get(id);

    void onProgress(int bytes) => _update(
      id,
      (o) => o.copyWith(
        bytes: bytes,
        stage:
            o.stage == OperationStage.checkingLicense ||
                o.stage == OperationStage.acquiringLicense
            ? OperationStage.downloading
            : o.stage,
      ),
    );

    _stage(id, OperationStage.checkingLicense);
    try {
      final result = await downloads.download(
        operation.app,
        staging,
        cancel: cancel,
        onProgress: onProgress,
      );
      _noteDownloading(id);
      return result.path;
    } on LicenseRequired {
      if (!operation.allowFreeLicense) rethrow;
    }

    // Apple's own "get" flow for a free app, on the user's say-so.
    _stage(id, OperationStage.acquiringLicense);
    try {
      final result = await downloads.download(
        operation.app,
        staging,
        allowPurchase: true,
        cancel: cancel,
        onProgress: onProgress,
      );
      _update(id, (o) => o.copyWith(licenseAcquired: result.licenseAcquired));
      _noteDownloading(id);
      return result.path;
    } on LicenseRequired {
      throw const LicenseRefused();
    }
  }

  /// Journals the download stage once, however fast the transfer was.
  void _noteDownloading(String id) {
    _update(id, (o) => o.copyWith(stage: OperationStage.downloading));
    ref
        .read(operationJournalProvider)
        .advance(id, OperationStage.downloading.name);
  }

  Future<void> _install(
    String id,
    String udid,
    Package package,
    CancelToken cancel,
  ) async {
    final devices = ref.read(deviceServiceProvider);
    final info = package.info;
    _stage(id, OperationStage.installing);
    _update(id, (o) => o.copyWith(installPercent: () => null));

    // The job is pinned to one device: never fall back to "whatever is
    // plugged in now".
    final device = (await devices.listDevices())
        .where((d) => d.udid == udid)
        .firstOrNull;
    if (device == null) throw const DeviceNotFound();

    final minimum = info.minimumOS;
    if (minimum != null &&
        device.osVersion.isNotEmpty &&
        compareVersions(device.osVersion, minimum) < 0) {
      throw const IncompatibleOS();
    }
    if (await _freeBytes(udid) case final free? when free < info.size) {
      throw const InsufficientSpace();
    }

    try {
      await for (final progress in devices.install(
        udid,
        package.path,
        cancel: cancel,
      )) {
        _update(id, (o) => o.copyWith(installPercent: () => progress.percent));
      }
    } on InstallResultUnknown {
      // Ask the device before deciding anything.
      _stage(id, OperationStage.verifying);
      final outcome = await _verify(udid, info);
      if (outcome == InstallOutcome.confirmed) {
        _update(id, (o) => o.copyWith(outcome: outcome));
        _stage(id, OperationStage.done, details: outcome.name);
      } else {
        _update(id, (o) => o.copyWith(error: const InstallResultUnknown()));
        _stage(id, OperationStage.unknown);
      }
      return;
    }

    _stage(id, OperationStage.verifying);
    final outcome = await _verify(udid, info);
    _update(id, (o) => o.copyWith(outcome: outcome));
    _stage(id, OperationStage.done, details: outcome.name);
  }

  /// Saves the package's own store artwork as the app's icon. Apps that
  /// left the store have no other source for one.
  Future<void> _keepArtwork(Package package) async {
    final appStoreId = package.appStoreId;
    if (appStoreId == null) return;
    final lookup = ref.read(lookupServiceProvider);
    if (lookup.hasIcon(appStoreId)) return;
    final bytes = await ref.read(ipaInspectorProvider).artwork(package.path);
    if (bytes == null) return;
    if (await lookup.saveIcon(appStoreId, bytes) != null) {
      ref.invalidate(appIconProvider(appStoreId));
    }
  }

  Future<int?> _freeBytes(String udid) async {
    try {
      return await ref.read(deviceServiceProvider).freeBytes(udid);
    } on AppError {
      return null; // Not knowing is no reason to refuse the install.
    }
  }

  Future<InstallOutcome> _verify(String udid, IpaInfo info) async {
    try {
      final installed = await ref
          .read(deviceServiceProvider)
          .installedApp(udid, info.bundleId);
      if (installed == null) return InstallOutcome.unverified;
      return info.displayVersion != null &&
              installed.version == info.displayVersion
          ? InstallOutcome.confirmed
          : InstallOutcome.versionUnknown;
    } on AppError {
      return InstallOutcome.unverified;
    }
  }

  static Future<void> _deleteDirectory(String path) async {
    try {
      await Directory(path).delete(recursive: true);
    } on FileSystemException {
      // Already gone.
    }
  }
}
