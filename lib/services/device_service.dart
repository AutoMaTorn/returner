import 'dart:async';
import 'dart:convert';

import '../core/cancel.dart';
import '../core/errors.dart';
import '../core/process_runner.dart';
import '../models/device.dart';
import 'device_errors.dart';

/// Finds connected iPhones and installs packages over USB with go-ios.
///
/// go-ios prints the command result as JSON on stdout and JSON log lines on
/// stderr; a recurring "agent is not running" warning there is harmless.
class DeviceService {
  DeviceService({required this._runner, required this._executable});

  static const _queryTimeout = Duration(seconds: 30);
  static const _fallbackName = 'iPhone';

  final ProcessRunner _runner;
  final String Function() _executable;
  final _names = <String, String>{};

  /// Connected devices. Throws [DriverMissing] when usbmuxd is unreachable.
  Future<List<Device>> listDevices() async {
    final result = await _run(['list', '--details']);
    final list = _lastJson(result.stdout)?['deviceList'];
    if (list is! List) return const [];

    final devices = <Device>[];
    for (final entry in list.whereType<Map<String, dynamic>>()) {
      final udid = entry['Udid'];
      if (udid is! String || udid.isEmpty) continue;
      devices.add(
        Device(
          udid: udid,
          name: await _deviceName(udid),
          productType: '${entry['ProductType'] ?? ''}',
          osVersion: '${entry['ProductVersion'] ?? ''}',
        ),
      );
    }
    _names.removeWhere((udid, _) => devices.every((d) => d.udid != udid));
    return devices;
  }

  /// Polls [listDevices] and emits when the set of devices changes. Errors
  /// (for example [DriverMissing]) are delivered as stream errors and polling
  /// continues.
  Stream<List<Device>> watchDevices({
    Duration interval = const Duration(seconds: 2),
  }) {
    // A controller rather than async*: a generator only notices cancellation
    // at a yield, and an unchanged device list never yields.
    late final StreamController<List<Device>> controller;
    Timer? timer;
    var active = false;
    List<Device>? previous;
    Type? previousError;

    Future<void> poll() async {
      try {
        final devices = await listDevices();
        if (!active) return;
        if (previous == null || !_sameDevices(previous!, devices)) {
          previous = devices;
          previousError = null;
          controller.add(devices);
        }
      } on AppError catch (error) {
        if (!active) return;
        if (error.runtimeType != previousError) {
          previous = null;
          previousError = error.runtimeType;
          controller.addError(error);
        }
      }
      if (active) timer = Timer(interval, poll);
    }

    controller = StreamController<List<Device>>(
      onListen: () {
        active = true;
        poll();
      },
      onCancel: () {
        active = false;
        timer?.cancel();
      },
    );
    return controller.stream;
  }

  static bool _sameDevices(List<Device> a, List<Device> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<String> _deviceName(String udid) async {
    final cached = _names[udid];
    if (cached != null) return cached;
    try {
      final result = await _run(['devicename', '--udid=$udid']);
      final name = _lastJson(result.stdout)?['devicename'];
      if (name is String && name.isNotEmpty) return _names[udid] = name;
    } on AppError {
      // A locked or half-paired device still deserves a row in the list.
    }
    return _fallbackName;
  }

  Future<int> freeBytes(String udid) async {
    final result = await _run(['diskspace', '--udid=$udid']);
    final free = _lastJson(result.stdout)?['FreeBytes'];
    if (free is! num) throw Unclassified('diskspace returned no FreeBytes');
    return free.toInt();
  }

  /// The installed app with [bundleId], or null if it is not on the device.
  Future<InstalledApp?> installedApp(String udid, String bundleId) async {
    final result = await _run(['apps', '--list', '--udid=$udid']);
    return parseAppList(result.stdout)
        .where((app) => app.bundleId == bundleId)
        .firstOrNull;
  }

  /// Parses `ios apps --list`: one app per line, `<bundle id> <name> <version>`.
  /// The name may contain spaces.
  static List<InstalledApp> parseAppList(String output) {
    final apps = <InstalledApp>[];
    for (final line in const LineSplitter().convert(output)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2 || !parts.first.contains('.')) continue;
      apps.add(
        InstalledApp(
          bundleId: parts.first,
          name: parts.length > 2
              ? parts.sublist(1, parts.length - 1).join(' ')
              : '',
          version: parts.last,
        ),
      );
    }
    return apps;
  }

  /// Installs [ipaPath] on the device with [udid].
  ///
  /// The stream first emits an indeterminate event (the file transfer reports
  /// nothing), then go-ios stages with percentages, and closes on success.
  /// Exit code 0 is not enough: an explicit "installation successful" line is
  /// required, otherwise the result is [InstallResultUnknown].
  Stream<InstallProgress> install(
    String udid,
    String ipaPath, {
    CancelToken? cancel,
  }) async* {
    if (cancel?.isCancelled ?? false) throw const Cancelled();
    final RunningProcess process;
    try {
      process = await _runner.start(_executable(), [
        'install',
        '--path=$ipaPath',
        '--udid=$udid',
      ]);
    } on ProcessStartFailure {
      throw const ComponentMissing('ios');
    }
    var cancelled = false;
    unawaited(
      cancel?.whenCancelled.then((_) {
        cancelled = true;
        process.kill();
      }),
    );
    unawaited(process.stdout.drain<void>());

    yield const InstallProgress(null, null);

    var succeeded = false;
    var transferFinished = false;
    final errors = <String>[];
    await for (final line in process.stderr) {
      final json = _json(line);
      if (json == null) continue;
      final level = '${json['level'] ?? ''}'.toUpperCase();
      final message = '${json['msg'] ?? ''}';
      if (level == 'ERROR' || level == 'FATAL') {
        errors.add('$message ${json['err'] ?? ''}'.trim());
      } else if (message == 'installation successful') {
        succeeded = true;
      } else if (json['percentComplete'] is num) {
        transferFinished = true;
        yield InstallProgress(
          (json['percentComplete'] as num).toInt(),
          json['status'] as String?,
        );
      }
    }
    final exitCode = await process.exitCode;

    if (cancelled) {
      // Once the device started processing the package we cannot know how
      // far it got.
      throw transferFinished ? const InstallResultUnknown() : const Cancelled();
    }
    if (errors.isNotEmpty) {
      final error = mapIosError(errors.join('\n'));
      throw error is Unclassified && transferFinished
          ? const InstallResultUnknown()
          : error;
    }
    if (exitCode != 0 || !succeeded) throw const InstallResultUnknown();
  }

  // --- plumbing --------------------------------------------------------------

  Future<ProcessOutput> _run(List<String> arguments) async {
    final ProcessOutput result;
    try {
      result = await _runner.run(
        _executable(),
        arguments,
        timeout: _queryTimeout,
      );
    } on ProcessStartFailure {
      throw const ComponentMissing('ios');
    } on ProcessTimeout {
      throw const DeviceNotFound();
    }
    final errors = [
      for (final line in const LineSplitter().convert(result.stderr))
        if (_json(line) case final json?)
          if (const {
            'ERROR',
            'FATAL',
          }.contains('${json['level'] ?? ''}'.toUpperCase()))
            '${json['msg'] ?? ''} ${json['err'] ?? ''}'.trim(),
    ];
    if (result.exitCode != 0 || errors.isNotEmpty) {
      throw mapIosError(errors.isNotEmpty ? errors.join('\n') : result.stderr);
    }
    return result;
  }

  static Map<String, dynamic>? _json(String line) {
    if (!line.trimLeft().startsWith('{')) return null;
    try {
      final value = jsonDecode(line);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }

  /// The result is the last JSON line of stdout.
  static Map<String, dynamic>? _lastJson(String stdout) {
    for (final line in const LineSplitter().convert(stdout).reversed) {
      final json = _json(line);
      if (json != null) return json;
    }
    return null;
  }
}
