import '../core/errors.dart';
import '../core/log.dart';

final _customerMessage = RegExp(r'"?CustomerMessage"?\s*[:=]\s*"([^"]+)"');

/// The reason Apple attached to a refusal, if any.
String? appleCustomerMessage(String output) {
  final message = _customerMessage.firstMatch(output)?[1]?.trim();
  return message == null || message.isEmpty ? null : message;
}

bool _any(String value, List<String> needles) => needles.any(value.contains);

final _urlPath = RegExp(r'(https?://[^/\s"?]+)[^\s"]*');

/// The longest network failure text kept for the log.
const networkCauseLimit = 300;

/// A network failure as one masked log line: which request failed and how,
/// e.g. `download Unicorn 2.1.4: … dial tcp: … connectex: …`.
String networkCause(String output, {bool duringLogin = false}) {
  final line = output
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      // The host is what tells connections apart; paths and queries only
      // add noise and, for signed downloads, secrets.
      .replaceAllMapped(_urlPath, (m) => '${m[1]}/…');
  final masked = duringLogin ? maskAuthOutput(line) : mask(line);
  return masked.length > networkCauseLimit
      ? '${masked.substring(0, networkCauseLimit)}…'
      : masked;
}

// ipatool appends Apple's button as " (<label>: <https url>)".
final _dialogAction = RegExp(
  r'^(.*?)\s*\(([^()]*): (https://[^\s()]+)\)\s*$',
  dotAll: true,
);

/// Splits a text ipatool marked as Apple's own into the message and the
/// apple.com page Apple's dialog button leads to. Any other link stays in
/// the text and is not offered as a link.
AppleSignInMessage appleSignInMessage(String text) {
  final trimmed = text.trim();
  final match = _dialogAction.firstMatch(trimmed);
  final uri = match == null ? null : Uri.tryParse(match[3]!);
  final host = uri?.host.toLowerCase() ?? '';
  final trusted =
      uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (host == 'apple.com' || host.endsWith('.apple.com'));
  final message = trusted ? match![1]!.trim() : trimmed;
  return AppleSignInMessage(
    message.isEmpty ? trimmed : message,
    link: trusted ? uri : null,
  );
}

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
    // Reported upstream (majd/ipatool#659): the saved session lacks this
    // computer's registration with Apple; signing in again creates it.
    'store amd state is not provisioned',
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
  // Observed 2026-11-07: Apple returns empty answers to every sign-in.
  if (_any(value, [
    'no usable authentication response',
    'empty or non-plist authentication response',
  ])) {
    return const AppleLoginRejected();
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
    return NetworkInterrupted(networkCause(output, duringLogin: duringLogin));
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
    return AppleUnreachable(networkCause(output, duringLogin: duringLogin));
  }

  // Checked last, so a network or session cause named in the same text wins.
  // The 403 is reported upstream (majd/ipatool#654, #656) for apps that left
  // the store; "no offer" is what our build says when both ways back failed.
  if (value.contains("no offer in the account's app store catalog") ||
      (value.contains('redownload request') && value.contains('http 403'))) {
    return const RedownloadRefused();
  }

  return Unclassified(mask(output.trim()));
}
