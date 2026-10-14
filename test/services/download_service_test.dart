import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:returner/core/cancel.dart';
import 'package:returner/core/errors.dart';
import 'package:returner/models/app_ref.dart';
import 'package:returner/models/store.dart';
import 'package:returner/services/download_service.dart';
import 'package:returner/services/ipatool_service.dart';

class _MockIpatool extends Mock implements IpatoolService {}

const _app = AppRef(appStoreId: '492224193');

void main() {
  late Directory temp;
  late _MockIpatool ipatool;
  late String staging;

  setUpAll(() => registerFallbackValue(_app));
  setUp(() {
    temp = Directory.systemTemp.createTempSync('returner_dl_');
    staging = '${temp.path}/staging/op-1';
    ipatool = _MockIpatool();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  DownloadService service({Duration? startupTimeout}) => DownloadService(
    ipatool,
    startupTimeout: startupTimeout ?? const Duration(seconds: 30),
    pollInterval: const Duration(milliseconds: 10),
    retryDelay: Duration.zero,
  );

  /// Scripts consecutive `ipatool download` calls.
  void script(
    List<Future<DownloadResult> Function(String output, CancelToken cancel)>
    attempts,
  ) {
    var index = 0;
    when(
      () => ipatool.download(
        any(),
        any(),
        allowPurchase: any(named: 'allowPurchase'),
        cancel: any(named: 'cancel'),
      ),
    ).thenAnswer((invocation) {
      final attempt =
          attempts[index < attempts.length ? index : attempts.length - 1];
      index++;
      return attempt(
        invocation.positionalArguments[1] as String,
        invocation.namedArguments[#cancel] as CancelToken,
      );
    });
  }

  /// Behaves like ipatool: grows `<output>.tmp`, then renames it.
  Future<DownloadResult> succeed(String output, CancelToken cancel) async {
    final tmp = File('$output.tmp');
    for (var i = 0; i < 3; i++) {
      tmp.writeAsBytesSync(List.filled(1000, 1), mode: FileMode.append);
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    tmp.renameSync(output);
    return DownloadResult(path: output, licenseAcquired: false);
  }

  Future<DownloadResult> Function(String, CancelToken) fail(AppError error) =>
      (output, cancel) async {
        File('$output.tmp').writeAsBytesSync([1, 2, 3]);
        throw error;
      };

  /// Never produces a byte; ends only when cancelled.
  Future<DownloadResult> stall(String output, CancelToken cancel) async {
    await cancel.whenCancelled;
    throw const Cancelled();
  }

  int calls() => verify(
    () => ipatool.download(
      any(),
      any(),
      allowPurchase: any(named: 'allowPurchase'),
      cancel: any(named: 'cancel'),
    ),
  ).callCount;

  test(
    'reports growing progress from the .tmp file and returns the file',
    () async {
      script([succeed]);
      final progress = <int>[];

      final result = await service().download(
        _app,
        staging,
        onProgress: progress.add,
      );

      expect(File(result.path).lengthSync(), 3000);
      expect(result.path, endsWith(DownloadService.fileName));
      expect(progress, isNotEmpty);
      expect(progress.last, 3000);
      expect([...progress]..sort(), progress, reason: 'never goes backwards');
      expect(File('${result.path}.tmp').existsSync(), isFalse);
    },
  );

  test('passes allowPurchase through', () async {
    script([succeed]);
    await service().download(_app, staging, allowPurchase: true);
    verify(
      () => ipatool.download(
        _app,
        any(),
        allowPurchase: true,
        cancel: any(named: 'cancel'),
      ),
    ).called(1);
  });

  test('retries a network failure and cleans the partial file', () async {
    script([fail(const NetworkInterrupted()), succeed]);
    final result = await service().download(_app, staging);
    expect(File(result.path).lengthSync(), 3000);
    expect(calls(), 2);
  });

  test('retries a corrupted archive', () async {
    script([fail(const PackageInvalid()), succeed]);
    await service().download(_app, staging);
    expect(calls(), 2);
  });

  test('gives up after three transient failures', () async {
    script([fail(const NetworkInterrupted())]);
    await expectLater(
      service().download(_app, staging),
      throwsA(isA<NetworkInterrupted>()),
    );
    expect(calls(), 3);
    expect(Directory(staging).listSync(), isEmpty);
  });

  for (final error in <AppError>[
    const LicenseRequired(),
    const AssetUnavailable(),
    const AuthSessionExpired(),
    const AuthInvalidCredentials(),
    const VersionUnavailable(),
  ]) {
    test('does not retry ${error.code}', () async {
      script([fail(error)]);
      await expectLater(
        service().download(_app, staging),
        throwsA(isA<AppError>().having((e) => e.code, 'code', error.code)),
      );
      expect(calls(), 1);
      expect(Directory(staging).listSync(), isEmpty);
    });
  }

  test('restarts once when the transfer never starts', () async {
    script([stall, succeed]);
    final result = await service(
      startupTimeout: const Duration(milliseconds: 60),
    ).download(_app, staging);
    expect(File(result.path).existsSync(), isTrue);
    expect(calls(), 2);
  });

  test('reports Apple as unreachable after two silent attempts', () async {
    script([stall]);
    await expectLater(
      service(startupTimeout: const Duration(milliseconds: 60))
          .download(_app, staging),
      throwsA(isA<AppleUnreachable>()),
    );
    expect(calls(), 2);
  });

  test('the startup watchdog leaves a running transfer alone', () async {
    script([
      (output, cancel) async {
        final tmp = File('$output.tmp')..writeAsBytesSync([1]);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(cancel.isCancelled, isFalse);
        tmp.renameSync(output);
        return DownloadResult(path: output, licenseAcquired: false);
      },
    ]);
    await service(startupTimeout: const Duration(milliseconds: 60))
        .download(_app, staging);
    expect(calls(), 1);
  });

  test(
    'user cancellation stops the process and removes partial files',
    () async {
      script([
        (output, cancel) async {
          File('$output.tmp').writeAsBytesSync(List.filled(500, 1));
          await cancel.whenCancelled;
          throw const Cancelled();
        },
      ]);
      final cancel = CancelToken();
      final download = service().download(_app, staging, cancel: cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      cancel.cancel();

      await expectLater(download, throwsA(isA<Cancelled>()));
      expect(calls(), 1);
      expect(Directory(staging).listSync(), isEmpty);
    },
  );

  test('a success without an output file is not a success', () async {
    script([
      (output, cancel) async =>
          DownloadResult(path: output, licenseAcquired: false),
    ]);
    await expectLater(
      service().download(_app, staging),
      throwsA(isA<PackageInvalid>()),
    );
  });
}
