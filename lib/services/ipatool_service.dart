import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/cancel.dart';
import '../core/errors.dart';
import '../core/log.dart';
import '../core/process_runner.dart';
import '../models/app_ref.dart';
import '../models/store.dart';
import 'ipatool_errors.dart';
import 'secure_store.dart';

/// Talks to the App Store through our patched ipatool build.
///
/// Secrets (keychain
/// passphrase, password, 2FA code) only ever travel through the child's
/// stdin.
class IpatoolService {
  IpatoolService({
    required this._runner,
    required this._executable,
    required this.stateDirectory,
    required this._secureStore,
  });

  static const loginTimeout = Duration(seconds: 360);

  /// `list-versions` and `get-version-metadata` take 20–40 s on a good day.
  static const queryTimeout = Duration(seconds: 120);
  static const _sessionFiles = ['account', 'cookies', 'kbsync-v1'];

  final ProcessRunner _runner;
  final String Function() _executable;
  final SecureStore _secureStore;

  /// Our own session directory (`IPATOOL_STATE_DIR`); never `~/.ipatool`.
  final String stateDirectory;

  /// Bumped whenever the signed-in account may have changed, so operations
  /// started under an older session can discard their results.
  int get generation => _generation;
  int _generation = 0;

  // --- account ---------------------------------------------------------------

  /// The saved account, or null when nobody is signed in.
  Future<AccountInfo?> currentAccount() async {
    try {
      final result = await _exec(['auth', 'info'], timeout: queryTimeout);
      return _account(result);
    } on AuthSessionExpired {
      return null;
    }
  }

  /// Signs in. Throws [AuthNeeds2FA] when Apple wants a code; call again with
  /// [code]. A session that cannot be decrypted is moved aside (not deleted)
  /// and the sign-in is retried once.
  Future<AccountInfo> login(
    String email,
    String password, {
    String? code,
    CancelToken? cancel,
  }) async {
    try {
      return await _login(email, password, code: code, cancel: cancel);
    } on StorageLocked {
      await _setAsideUnreadableSession();
      return _login(email, password, code: code, cancel: cancel);
    }
  }

  Future<AccountInfo> _login(
    String email,
    String password, {
    String? code,
    CancelToken? cancel,
  }) async {
    final lines = await _exec(
      ['auth', 'login', '--email', email],
      secrets: {
        'password': password,
        if (code != null && code.isNotEmpty) 'auth-code': code,
      },
      timeout: loginTimeout,
      cancel: cancel,
      duringLogin: true,
    );
    if (lines.every((line) => line['success'] != true)) {
      // Without a code ipatool exits 0 and only prints a hint.
      final text = lines.map((line) => line['message'] ?? '').join('\n');
      final error = mapIpatoolError(text, duringLogin: true);
      throw error is Unclassified ? const AuthNeeds2FA() : error;
    }
    _generation++;

    // Trust the saved session, not just the exit code.
    final saved = await currentAccount();
    if (saved == null) throw const StorageLocked();
    if (email.contains('@') &&
        saved.email.toLowerCase() != email.trim().toLowerCase()) {
      throw const StorageLocked();
    }
    return saved;
  }

  /// Removes the saved session. Downloaded packages are not touched.
  Future<void> logout() async {
    try {
      await _exec(['auth', 'revoke'], timeout: queryTimeout);
    } on AuthSessionExpired {
      // Already signed out.
    } finally {
      _generation++;
    }
  }

  // --- catalog ---------------------------------------------------------------

  /// One page of the apps this account owns, newest first.
  Future<PurchasePage> purchases({int page = 1, int pageSize = 50}) async {
    final result = await _exec([
      'list-purchases',
      '--max-results',
      '$pageSize',
      '--page',
      '$page',
      '--platform',
      'iphone',
    ], timeout: queryTimeout);
    final line = _last(result);
    return PurchasePage(
      apps: _apps(line),
      page: (line['page'] as num?)?.toInt() ?? page,
      totalCount: (line['totalCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Text search; only finds apps that still have a store page.
  Future<List<StoreApp>> search(String term, {int limit = 20}) async {
    final result = await _exec(
      // "--" keeps a term that starts with a dash from being read as a flag.
      ['search', '--limit', '$limit', '--', term],
      timeout: queryTimeout,
    );
    return _apps(_last(result));
  }

  /// External version ids, oldest first.
  Future<List<String>> listVersions(AppRef app) async {
    final result = await _exec([
      'list-versions',
      ..._appArgs(app),
    ], timeout: queryTimeout);
    final ids = _last(result)['externalVersionIdentifiers'];
    return ids is List ? [for (final id in ids) '$id'] : const [];
  }

  Future<VersionMetadata> versionMetadata(
    AppRef app,
    String externalVersionId,
  ) async {
    final result = await _exec([
      'get-version-metadata',
      ..._appArgs(app),
      '--external-version-id',
      externalVersionId,
    ], timeout: queryTimeout);
    final line = _last(result);
    return VersionMetadata(
      externalVersionId: '${line['externalVersionID'] ?? externalVersionId}',
      displayVersion: '${line['displayVersion'] ?? ''}',
      releaseDate: DateTime.tryParse('${line['releaseDate'] ?? ''}'),
    );
  }

  // --- download --------------------------------------------------------------

  /// Downloads one package to [outputPath]. While the transfer runs ipatool
  /// writes to `<outputPath>.tmp` and reports nothing; callers watch the file
  /// size. With [allowPurchase] a missing free license is obtained first.
  Future<DownloadResult> download(
    AppRef app,
    String outputPath, {
    bool allowPurchase = false,
    CancelToken? cancel,
  }) async {
    final result = await _exec([
      'download',
      ..._appArgs(app),
      '--output',
      outputPath,
      if (allowPurchase) '--purchase',
      if (app.externalVersionId != null) ...[
        '--external-version-id',
        app.externalVersionId!,
      ],
    ], cancel: cancel);
    final line = _last(result);
    if (line['success'] != true) {
      throw Unclassified(mask(jsonEncode(line)));
    }
    return DownloadResult(
      path: outputPath,
      licenseAcquired: line['purchased'] == true,
    );
  }

  // --- plumbing --------------------------------------------------------------

  static List<String> _appArgs(AppRef app) => app.appStoreId != null
      ? ['--app-id', app.appStoreId!]
      : ['--bundle-identifier', app.bundleId!];

  static Map<String, dynamic> _last(List<Map<String, dynamic>> lines) =>
      lines.isEmpty ? const {} : lines.last;

  static AccountInfo _account(List<Map<String, dynamic>> lines) {
    final line = lines.lastWhere(
      (l) => l['email'] is String,
      orElse: () => throw const AuthSessionExpired(),
    );
    return AccountInfo(
      email: line['email'] as String,
      name: '${line['name'] ?? ''}',
    );
  }

  static List<StoreApp> _apps(Map<String, dynamic> line) {
    final apps = line['apps'];
    if (apps is! List) return const [];
    return [
      for (final app in apps.whereType<Map<String, dynamic>>())
        StoreApp(
          appStoreId: '${app['id']}',
          bundleId: '${app['bundleID'] ?? ''}',
          name: '${app['name'] ?? ''}',
          version: app['version'] as String?,
          price: app['price'] as num?,
          purchaseDate: DateTime.tryParse('${app['purchaseDate'] ?? ''}'),
          platforms: [...?(app['platforms'] as List?)?.map((e) => '$e')],
        ),
    ];
  }

  /// Runs one ipatool command and returns its JSON lines.
  ///
  /// Throws a mapped [AppError] on an error line or a non-zero exit code.
  Future<List<Map<String, dynamic>>> _exec(
    List<String> command, {
    Map<String, String> secrets = const {},
    Duration? timeout,
    CancelToken? cancel,
    bool duringLogin = false,
  }) async {
    if (cancel?.isCancelled ?? false) throw const Cancelled();
    final passphrase = await _secureStore.keychainPassphrase();
    await Directory(stateDirectory).create(recursive: true);

    final String executable;
    final RunningProcess process;
    try {
      executable = _executable();
      process = await _runner.start(
        executable,
        [
          ...command,
          '--format',
          'json',
          '--non-interactive',
          '--credentials-stdin',
        ],
        environment: {'IPATOOL_STATE_DIR': stateDirectory},
        stdin:
            '${jsonEncode({'keychain-passphrase': passphrase, ...secrets})}\n',
      );
    } on ProcessStartFailure {
      throw const ComponentMissing('ipatool');
    }

    final stdoutLines = <String>[];
    final stderrLines = <String>[];
    final drained = Future.wait([
      process.stdout.forEach(stdoutLines.add),
      process.stderr.forEach(stderrLines.add),
    ]);

    var cancelled = false;
    var timedOut = false;
    unawaited(
      cancel?.whenCancelled.then((_) {
        cancelled = true;
        process.kill();
      }),
    );
    final timer = timeout == null
        ? null
        : Timer(timeout, () {
            timedOut = true;
            process.kill();
          });

    final int exitCode;
    try {
      exitCode = await process.exitCode;
      await drained;
    } finally {
      timer?.cancel();
    }
    if (cancelled) throw const Cancelled();
    if (timedOut) throw const AppleUnreachable();

    final lines = _jsonLines(stdoutLines);
    final errorLine = lines.where((l) => l['level'] == 'error').lastOrNull;
    if (errorLine != null) {
      final metadata = errorLine['metadata'];
      throw mapIpatoolError(
        '${errorLine['error'] ?? ''}'
        '${metadata == null ? '' : ' metadata=${jsonEncode(metadata)}'}',
        duringLogin: duringLogin,
      );
    }
    if (exitCode != 0) {
      // No structured error: a crash or output we do not understand.
      final tail = [...stdoutLines, ...stderrLines].join('\n');
      throw mapIpatoolError(
        tail.length > 2000 ? tail.substring(tail.length - 2000) : tail,
        duringLogin: duringLogin,
      );
    }
    return lines;
  }

  static List<Map<String, dynamic>> _jsonLines(List<String> lines) {
    final result = <Map<String, dynamic>>[];
    for (final line in lines) {
      if (!line.trimLeft().startsWith('{')) continue;
      try {
        final value = jsonDecode(line);
        if (value is Map<String, dynamic>) result.add(value);
      } on FormatException {
        // Not a protocol line.
      }
    }
    return result;
  }

  /// Moves an undecryptable session into a sibling backup directory so a new
  /// sign-in can start clean without destroying anything.
  Future<void> _setAsideUnreadableSession() async {
    final backup = Directory(
      '$stateDirectory.unreadable-${DateTime.now().millisecondsSinceEpoch}',
    );
    for (final name in _sessionFiles) {
      final file = File(p.join(stateDirectory, name));
      if (!file.existsSync()) continue;
      await backup.create(recursive: true);
      await file.rename(p.join(backup.path, name));
    }
    Log.warning('Unreadable App Store session was moved to a backup folder.');
  }
}
