import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/log.dart';
import '../services/update_service.dart';
import 'settings.dart';

final updateServiceProvider = Provider<UpdateService>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return UpdateService(client: client, currentVersion: appVersion);
});

/// Whether Returner asks GitHub for a newer release on start. On by default;
/// the user can turn the request off.
final checkUpdatesOnStartProvider =
    NotifierProvider<CheckUpdatesOnStartController, bool>(
      CheckUpdatesOnStartController.new,
    );

class CheckUpdatesOnStartController extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(settingsFileProvider).read()['checkUpdates'] != false;

  void set(bool value) {
    state = value;
    ref.read(settingsFileProvider).put('checkUpdates', value);
  }
}

enum UpdateStatus { idle, checking, upToDate, available, failed }

class UpdateState {
  const UpdateState(this.status, {this.update});

  final UpdateStatus status;

  /// Set when [status] is [UpdateStatus.available].
  final AvailableUpdate? update;
}

final updatesProvider = NotifierProvider<UpdatesController, UpdateState>(
  UpdatesController.new,
);

class UpdatesController extends Notifier<UpdateState> {
  var _startChecked = false;

  @override
  UpdateState build() => const UpdateState(UpdateStatus.idle);

  /// The automatic check: once per run, and only if the user allows it.
  Future<void> checkOnStart() async {
    if (_startChecked) return;
    _startChecked = true;
    if (!ref.read(checkUpdatesOnStartProvider)) return;
    await check();
  }

  Future<void> check() async {
    if (state.status == UpdateStatus.checking) return;
    state = const UpdateState(UpdateStatus.checking);
    try {
      final update = await ref.read(updateServiceProvider).check();
      if (update == null) {
        state = const UpdateState(UpdateStatus.upToDate);
      } else {
        Log.info('Update available: ${update.version}');
        state = UpdateState(UpdateStatus.available, update: update);
      }
    } on UpdateCheckFailed {
      Log.info('Update check failed');
      state = const UpdateState(UpdateStatus.failed);
    }
  }
}
