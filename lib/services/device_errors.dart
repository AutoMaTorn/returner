import '../core/errors.dart';
import '../core/log.dart';

final _usbmuxd = RegExp(r'dial tcp 127\.0\.0\.1:27015');

bool _matches(String value, String pattern) =>
    RegExp(pattern, caseSensitive: false).hasMatch(value);

/// Maps go-ios error text to a typed error.
///
/// Only the missing-driver case is confirmed by real output; the rest are
/// hypotheses from installation_proxy error names and reports seen in the
/// wild, to be confirmed against real output.
AppError mapIosError(String output) {
  // Observed on Windows without Apple Mobile Device Service. The text after
  // "connectex:" is localized, so only the address is matched.
  if (_usbmuxd.hasMatch(output)) return const DriverMissing();

  // Must come before the "locked" check: these messages also mention
  // streaming_zip_conduit.
  if (_matches(
    output,
    r'does not match installed application|application-identifier|rejecting upgrade|'
    r'mismatched.*(entitlement|identifier)|coordinated (app )?install .*exist|code=46|coordinatorscope',
  )) {
    return const InstallConflict();
  }
  if (_matches(
    output,
    r'passwordprotected|password[- ]?protected|devicelocked|device is (pass ?code )?locked',
  )) {
    return const DeviceLocked();
  }
  if (_matches(
    output,
    r'pairing failed|pair ?record|invalidhostid|untrusted host|not paired|userdeniedpairing|pairingdialogresponsepending',
  )) {
    return const DeviceNotTrusted();
  }
  if (_matches(
    output,
    r'kamdnospaceerror|no ?space|not enough (space|storage)|insufficient (space|storage)|disk ?full',
  )) {
    return const InsufficientSpace();
  }
  if (_matches(
    output,
    r'deviceosversiontoolow|minimum ?os|incompatible.*(os|device)|requires (a newer|ios)',
  )) {
    return const IncompatibleOS();
  }
  if (_matches(
    output,
    r'device not found|no device found|not found in device list|is it attached|device .* not (connected|attached)',
  )) {
    return const DeviceNotFound();
  }
  if (_matches(
    output,
    r'applicationverificationfailed|installprohibited|apiinternalerror|packageinspectionfailed|mierror|installation failed',
  )) {
    return const InstallRejected();
  }
  return Unclassified(mask(output.trim()));
}
