import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mocktail/mocktail.dart';
import 'package:returner/core/errors.dart';
import 'package:returner/models/store.dart';
import 'package:returner/services/ipatool_service.dart';
import 'package:returner/state/components.dart';
import 'package:returner/state/providers.dart';

class _MockIpatool extends Mock implements IpatoolService {}

// `unit` level.
void main() {
  late _MockIpatool ipatool;
  late ProviderContainer container;

  setUp(() {
    ipatool = _MockIpatool();
    container = ProviderContainer(
      overrides: [ipatoolServiceProvider.overrideWithValue(ipatool)],
    );
  });
  tearDown(() => container.dispose());

  ComponentsController controller() =>
      container.read(componentsProvider.notifier);
  ComponentsState state() => container.read(componentsProvider);

  void prepareAnswers(Future<void> Function(Invocation call) answer) => when(
    () => ipatool.prepareComponents(
      onProgress: any(named: 'onProgress'),
      cancel: any(named: 'cancel'),
    ),
  ).thenAnswer(answer);

  test('cached components need no download', () async {
    when(() => ipatool.componentsReady()).thenAnswer((_) async => true);
    await controller().ensure();
    expect(state().status, ComponentsStatus.ready);
    expect(state().blocksSignIn, isFalse);
    verifyNever(
      () => ipatool.prepareComponents(onProgress: any(named: 'onProgress')),
    );
  });

  test('missing components are downloaded, stage by stage', () async {
    when(() => ipatool.componentsReady()).thenAnswer((_) async => false);
    final release = Completer<void>();
    final seen = <ComponentsState>[];
    container.listen(componentsProvider, (_, next) => seen.add(next));
    prepareAnswers((call) async {
      final onProgress =
          call.namedArguments[#onProgress] as void Function(ComponentsProgress);
      onProgress(const ComponentsProgress(ComponentStage.runtime, total: 300));
      onProgress(
        const ComponentsProgress(
          ComponentStage.appleAssets,
          bytes: 120,
          total: 300,
        ),
      );
      await release.future;
    });

    final running = controller().ensure();
    await Future<void>.delayed(Duration.zero);
    expect(state().status, ComponentsStatus.downloading);
    expect(state().stage, ComponentStage.appleAssets);
    expect(state().bytes, 120);
    expect(state().fraction, closeTo(0.4, 1e-9));
    expect(state().blocksSignIn, isTrue);

    // A second call while one runs does not start another download.
    await controller().ensure();
    release.complete();
    await running;

    expect(state().status, ComponentsStatus.ready);
    expect(seen.map((s) => s.stage), contains(ComponentStage.runtime));
    verify(
      () => ipatool.prepareComponents(onProgress: any(named: 'onProgress')),
    ).called(1);
  });

  test('a failure is logged with its cause and can be retried', () async {
    final records = <LogRecord>[];
    final subscription = Logger('returner').onRecord.listen(records.add);
    addTearDown(subscription.cancel);
    when(() => ipatool.componentsReady()).thenAnswer((_) async => false);
    prepareAnswers(
      (_) async => throw const AppleUnreachable('dial tcp: github.com'),
    );

    await controller().ensure();
    expect(state().status, ComponentsStatus.failed);
    expect(state().error, isA<AppleUnreachable>());
    expect(state().blocksSignIn, isFalse);
    expect(
      records.map((r) => r.message),
      contains('Components failed: APPLE_UNREACHABLE — dial tcp: github.com'),
    );

    prepareAnswers((_) async {});
    await controller().ensure();
    expect(state().status, ComponentsStatus.ready);
  });

  group('time left', () {
    ComponentsState at(int bytes, int seconds, {int total = 300}) =>
        ComponentsState(
          ComponentsStatus.downloading,
          bytes: bytes,
          total: total,
          elapsed: Duration(seconds: seconds),
        );

    test('follows the average speed so far', () {
      // 100 of 300 in 10 s: the other 200 take about 20 s.
      expect(at(100, 10).remaining, const Duration(seconds: 20));
    });

    test('is not guessed from the first seconds or without a size', () {
      expect(at(100, 2).remaining, isNull);
      expect(at(0, 10).remaining, isNull);
      expect(at(100, 10, total: 0).remaining, isNull);
      expect(at(100, 10, total: 0).fraction, isNull);
    });

    test('is zero once the expected bytes are in', () {
      expect(at(320, 10).remaining, Duration.zero);
      expect(at(320, 10).fraction, 1.0);
    });
  });
}
