import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/cancel.dart';
import '../core/errors.dart';
import '../core/log.dart';
import '../models/app_ref.dart';
import '../models/store.dart';
import 'ipatool_service.dart';

/// Runs an ipatool download reliably: progress from the output file size, a
/// watchdog for transfers that never start, bounded retries for transient
/// failures, and cleanup of partial files.
class DownloadService {
  DownloadService(
    this._ipatool, {
    this.startupTimeout = const Duration(seconds: 120),
    this.pollInterval = const Duration(milliseconds: 350),
    this.maxAttempts = 3,
    this.retryDelay = const Duration(seconds: 2),
  });

  static const fileName = 'download.ipa';

  final IpatoolService _ipatool;

  /// How long to wait for the first byte before restarting the request once.
  final Duration startupTimeout;
  final Duration pollInterval;
  final int maxAttempts;

  /// Base pause between attempts; multiplied by the attempt number.
  final Duration retryDelay;

  /// Downloads [app] into [stagingDirectory] and returns the finished file.
  ///
  /// [onProgress] receives the bytes written so far. Wrong credentials, a
  /// missing license or an unavailable app are never retried.
  Future<DownloadResult> download(
    AppRef app,
    String stagingDirectory, {
    bool allowPurchase = false,
    CancelToken? cancel,
    void Function(int bytes)? onProgress,
  }) async {
    await Directory(stagingDirectory).create(recursive: true);
    final output = p.join(stagingDirectory, fileName);

    var startupRestarted = false;
    for (var attempt = 1; ; attempt++) {
      await _removeArtifacts(output);
      try {
        final result = await _attempt(
          app,
          output,
          allowPurchase: allowPurchase,
          cancel: cancel,
          onProgress: onProgress,
        );
        if (!File(output).existsSync()) throw const PackageInvalid();
        return result;
      } on Cancelled {
        await _removeArtifacts(output);
        rethrow;
      } on _StartupTimeout {
        await _removeArtifacts(output);
        if (startupRestarted) throw const AppleUnreachable();
        startupRestarted = true;
        Log.warning('App Store did not start the transfer; retrying once.');
      } on AppError catch (error) {
        await _removeArtifacts(output);
        final transient =
            error is NetworkInterrupted || error is PackageInvalid;
        if (!transient || attempt >= maxAttempts) rethrow;
        Log.warning('Download attempt $attempt failed (${error.code}).');
        await _sleep(retryDelay * attempt, cancel);
      }
    }
  }

  Future<DownloadResult> _attempt(
    AppRef app,
    String output, {
    required bool allowPurchase,
    CancelToken? cancel,
    void Function(int bytes)? onProgress,
  }) async {
    // Separate token: the watchdog must be able to stop the process without
    // it looking like a user cancellation.
    final processCancel = CancelToken();
    unawaited(cancel?.whenCancelled.then((_) => processCancel.cancel()));

    var startupTimedOut = false;
    var lastBytes = 0;
    final watch = Stopwatch()..start();
    final poller = Timer.periodic(pollInterval, (_) {
      final bytes = _artifactBytes(output);
      if (bytes > lastBytes) {
        lastBytes = bytes;
        onProgress?.call(bytes);
      }
      if (lastBytes == 0 && watch.elapsed > startupTimeout) {
        startupTimedOut = true;
        processCancel.cancel();
      }
    });

    try {
      final result = await _ipatool.download(
        app,
        output,
        allowPurchase: allowPurchase,
        cancel: processCancel,
      );
      // Exact size, even if lower: merging parts can briefly count one twice.
      final finalBytes = _artifactBytes(output);
      if (finalBytes != lastBytes) onProgress?.call(finalBytes);
      return result;
    } on Cancelled {
      if (startupTimedOut && !(cancel?.isCancelled ?? false)) {
        throw const _StartupTimeout();
      }
      rethrow;
    } finally {
      poller.cancel();
    }
  }

  /// Where ipatool stages the extra ranges of a large parallel download
  /// before appending them to `.tmp`.
  static String _partsPath(String output) => '$output.tmp.ipatool-parts';

  /// Size of the output, or of `.tmp` plus staged parts, whichever is larger.
  static int _artifactBytes(String output) {
    int sizeOf(File file) {
      try {
        return file.lengthSync();
      } on FileSystemException {
        return 0; // Not created yet, or just renamed or merged.
      }
    }

    var staged = sizeOf(File('$output.tmp'));
    try {
      for (final part in Directory(_partsPath(output)).listSync()) {
        if (part is File) staged += sizeOf(part);
      }
    } on FileSystemException {
      // No parallel download in progress.
    }
    final done = sizeOf(File(output));
    return done > staged ? done : staged;
  }

  static Future<void> _removeArtifacts(String output) async {
    for (final path in [output, '$output.tmp']) {
      try {
        await File(path).delete();
      } on FileSystemException {
        // Nothing to remove.
      }
    }
    // A killed ipatool leaves its staging directory behind.
    try {
      await Directory(_partsPath(output)).delete(recursive: true);
    } on FileSystemException {
      // Nothing to remove.
    }
  }

  static Future<void> _sleep(Duration duration, CancelToken? cancel) async {
    if (cancel == null) return Future<void>.delayed(duration);
    await Future.any([Future<void>.delayed(duration), cancel.whenCancelled]);
    if (cancel.isCancelled) throw const Cancelled();
  }
}

class _StartupTimeout implements Exception {
  const _StartupTimeout();
}
