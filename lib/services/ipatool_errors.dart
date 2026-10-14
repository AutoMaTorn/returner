import '../core/errors.dart';
import '../core/log.dart';

final _customerMessage = RegExp(r'"?CustomerMessage"?\s*[:=]\s*"([^"]+)"');

/// The reason Apple attached to a refusal, if any.
String? appleCustomerMessage(String output) {
  final message = _customerMessage.firstMatch(output)?[1]?.trim();
  return message == null || message.isEmpty ? null : message;
}

bool _any(String value, List<String> needles) => needles.any(value.contains);

/// Maps an ipatool error text to a typed error.
///
/// Strings marked "observed" come from real output; the rest are hypotheses
/// taken from ipatool's sources and from error reports seen in the wild.
/// [duringLogin] changes how a request for a 2FA code is read: while signing
/// in it is the next step, anywhere else it means the session is gone.
AppError mapIpatoolError(String output, {bool duringLogin = false}) {
  final value = output.toLowerCase();

  // Observed: the keychain file was encrypted with another passphrase.
  if (_any(value, ['aes.keyunwrap', 'integrity check failed'])) {
    return const StorageLocked();
  }
  // Observed: no saved account.
  if (_any(value, ['could not be found in the keyring', 'not logged in'])) {
    return const AuthSessionExpired();
  }
  if (_any(value, [
    '2fa code is required',
    'auth code is required',
    'two-factor auth code required',
  ])) {
    return duringLogin ? const AuthNeeds2FA() : const AuthSessionExpired();
  }
  if (_any(value, [
    'password token is expired',
    'passwordtokenexpired',
    'session expired',
  ])) {
    return const AuthSessionExpired();
  }
  if ((value.contains('failuretype') && value.contains('5005')) ||
      _any(value, ['invalid verification code', 'incorrect verification'])) {
    return const AuthInvalidCode();
  }
  if ((value.contains('failuretype') && value.contains('5020')) ||
      _any(value, [
        'did you forget your password',
        'incorrect password',
        'bad login',
        'invalid credentials',
      ])) {
    return const AuthInvalidCredentials();
  }
  if ((value.contains('too many') && value.contains('attempt')) ||
      value.contains('account locked')) {
    return const AuthRateLimited();
  }
  if (value.contains('invalid response') &&
      RegExp(r'store-front[^,]{0,20}null').hasMatch(value)) {
    return const AccountNotReady();
  }

  if (_any(value, [
    'license is required',
    'license required',
    'no license',
    'you must purchase this app first',
  ])) {
    return const LicenseRequired();
  }
  final reason = appleCustomerMessage(output);
  if (_any(value, ['failed to purchase', 'paid apps'])) {
    return LicenseRefused(reason);
  }
  // Observed: a display version id that does not belong to the app.
  if (value.contains('does not match the requested app or version')) {
    return const VersionUnavailable();
  }
  // "app not found" is observed for an unknown bundle id.
  if (_any(value, [
        'item is temporarily unavailable',
        'item is unavailable',
        'app not found',
      ]) ||
      (reason != null &&
          _any(reason.toLowerCase(), [
            'not available',
            'no longer available',
          ]))) {
    return AssetUnavailable(reason);
  }

  if (_any(value, [
    'not a valid zip file',
    'failed to open zip reader',
    'failed to replicate zip',
  ])) {
    return const PackageInvalid();
  }
  if (_any(value, [
    'no space left',
    'not enough space',
    'disk full',
    'disk is full',
  ])) {
    return const DiskFull();
  }
  if (_any(value, [
    'connection reset',
    'connection was reset',
    'network is unreachable',
    'i/o timeout',
    'request timeout',
    'timed out',
    'unexpected eof',
    'temporary failure',
    'wsarecv',
    'forcibly closed',
  ])) {
    return const NetworkInterrupted();
  }
  if (_any(value, [
        'failed to get bag',
        'tls: ',
        'tls handshake',
        'failed to make round trip',
        'no such host',
        'server misbehaving',
        'dial tcp',
        'connection refused',
      ]) ||
      (value.contains('x509') && value.contains('certificate'))) {
    return const AppleUnreachable();
  }

  return Unclassified(mask(output.trim()));
}
