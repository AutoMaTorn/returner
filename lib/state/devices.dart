import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import 'providers.dart';

/// Connected devices, refreshed every couple of seconds. A missing Apple
/// driver surfaces as an error value.
final devicesProvider = StreamProvider<List<Device>>(
  (ref) => ref.watch(deviceServiceProvider).watchDevices(),
);

/// UDID picked by the user; null means "the only connected device".
final selectedUdidProvider = NotifierProvider<SelectedUdid, String?>(
  SelectedUdid.new,
);

class SelectedUdid extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? udid) => state = udid;
}

/// The device operations should target right now, if it is unambiguous.
final currentDeviceProvider = Provider<Device?>((ref) {
  final devices = ref.watch(devicesProvider).value ?? const <Device>[];
  final selected = ref.watch(selectedUdidProvider);
  if (selected != null) {
    return devices.where((d) => d.udid == selected).firstOrNull;
  }
  return devices.length == 1 ? devices.single : null;
});
