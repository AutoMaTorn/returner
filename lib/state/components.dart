import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../core/log.dart';
import '../models/store.dart';
import 'providers.dart';

enum ComponentsStatus {
  /// Not looked at yet, or the offline check is running.
  checking,
  downloading,
  ready,

  /// The download failed. Signing in stays possible: ipatool then tries to
  /// fetch the components itself, as it did before this step existed.
  failed,
}

class ComponentsState {
  const ComponentsState(
    this.status, {
    this.stage,
    this.bytes = 0,
    this.total = 0,
    this.elapsed = Duration.zero,
    this.error,
  });

  final ComponentsStatus status;

  /// The component being downloaded; null before ipatool names one.
  final ComponentStage? stage;

  /// Bytes of this download that have arrived, out of about [total]
  /// (zero when the size is not known).
  final int bytes;
  final int total;

  /// Time since the download started, as of the last report.
  final Duration elapsed;
  final AppError? error;

  /// Signing in now would only wait for the same download.
  bool get blocksSignIn =>
      status == ComponentsStatus.checking ||
      status == ComponentsStatus.downloading;

  /// Share of [total] that has arrived, or null when the size is not known.
  double? get fraction =>
      total > 0 ? (bytes / total).clamp(0.0, 1.0).toDouble() : null;

  /// About how long the rest takes at the average speed so far; null until
  /// a few seconds of data make that meaningful. Zero once the expected
  /// bytes are all in but ipatool is still unpacking them.
  Duration? get remaining {
    if (status != ComponentsStatus.downloading || total <= 0) return null;
    if (elapsed < estimateAfter || bytes <= 0) return null;
    final left = total - bytes;
    if (left <= 0) return Duration.zero;
    return Duration(
      microseconds: (left * elapsed.inMicroseconds / bytes).round(),
    );
  }

  /// The first seconds of a download say little about its speed.
  static const estimateAfter = Duration(seconds: 3);
}

/// The components ipatool needs before its first sign-in on this computer.
/// Fetched as a step of their own so the sign-in timeout does not have to
/// cover a slow download, and a failure names the connection that broke.
final componentsProvider =
    NotifierProvider<ComponentsController, ComponentsState>(
      ComponentsController.new,
    );

class ComponentsController extends Notifier<ComponentsState> {
  var _running = false;

  @override
  ComponentsState build() => const ComponentsState(ComponentsStatus.checking);

  /// Checks the cache and downloads what is missing. Safe to call again.
  Future<void> ensure() async {
    if (_running || state.status == ComponentsStatus.ready) return;
    _running = true;
    final ipatool = ref.read(ipatoolServiceProvider);
    state = const ComponentsState(ComponentsStatus.checking);
    try {
      if (await ipatool.componentsReady()) {
        state = const ComponentsState(ComponentsStatus.ready);
        return;
      }
      Log.info('Components: missing, downloading before sign-in');
      state = const ComponentsState(ComponentsStatus.downloading);
      final watch = Stopwatch()..start();
      await ipatool.prepareComponents(
        onProgress: (progress) => state = ComponentsState(
          ComponentsStatus.downloading,
          stage: progress.stage,
          bytes: progress.bytes,
          total: progress.total,
          elapsed: watch.elapsed,
        ),
      );
      state = const ComponentsState(ComponentsStatus.ready);
    } on AppError catch (error) {
      Log.warning(
        'Components failed: ${error.code}'
        '${error.logDetails == null ? '' : ' — ${error.logDetails}'}',
      );
      state = ComponentsState(ComponentsStatus.failed, error: error);
    } finally {
      _running = false;
    }
  }
}
