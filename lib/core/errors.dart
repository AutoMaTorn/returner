/// Typed failures shown to the user. Services map raw tool output to these.
///
/// [code] is a stable identifier for the operation journal; user-facing text
/// lives in `lib/ui/strings.dart`.
sealed class AppError implements Exception {
  const AppError(this.code);

  final String code;

  /// Masked text for the log and the journal that says more than [code];
  /// never shown to the user.
  String? get logDetails => null;

  @override
  String toString() => 'AppError($code)';
}

// --- Apple ID session -------------------------------------------------------

class AuthInvalidCredentials extends AppError {
  const AuthInvalidCredentials() : super('AUTH_REJECTED');
}

class AuthNeeds2FA extends AppError {
  const AuthNeeds2FA() : super('TWO_FACTOR_REQUIRED');
}

class AuthInvalidCode extends AppError {
  const AuthInvalidCode() : super('TWO_FACTOR_REJECTED');
}

class AuthRateLimited extends AppError {
  const AuthRateLimited() : super('RATE_LIMITED');
}

class AuthSessionExpired extends AppError {
  const AuthSessionExpired() : super('SESSION_EXPIRED');
}

/// The saved session or its key cannot be read; the data is left untouched.
class StorageLocked extends AppError {
  const StorageLocked() : super('STORAGE_LOCKED');
}

/// No answer from Apple, or from the servers ipatool fetches its components
/// from. [cause] (masked) says which connection failed and how.
class AppleUnreachable extends AppError {
  const AppleUnreachable([this.cause]) : super('APPLE_UNREACHABLE');

  final String? cause;

  @override
  String? get logDetails => cause;
}

/// Apple answers the sign-in request with nothing usable (empty 204, 404),
/// whatever the password. Seen on 2026-11-07 for every account: Apple changed
/// what it accepts, and only an ipatool update can fix it.
class AppleLoginRejected extends AppError {
  const AppleLoginRejected() : super('APPLE_LOGIN_REJECTED');
}

/// Apple refused the sign-in and explained why in its own words: a sign-in
/// dialog (a locked account, a password reset) or a customer message.
/// [link] is an https page on apple.com that Apple offered, if any.
class AppleSignInMessage extends AppError {
  const AppleSignInMessage(this.message, {this.link})
    : super('APPLE_SIGN_IN_MESSAGE');

  final String message;
  final Uri? link;
}

/// The account has not accepted the App Store terms or has no storefront.
class AccountNotReady extends AppError {
  const AccountNotReady() : super('ACCOUNT_NOT_READY');
}

// --- License and download ---------------------------------------------------

class LicenseRequired extends AppError {
  const LicenseRequired() : super('LICENSE_REQUIRED');
}

class LicenseRefused extends AppError {
  const LicenseRefused([this.appleMessage])
    : super('LICENSE_ACQUISITION_REFUSED');

  final String? appleMessage;
}

class AssetUnavailable extends AppError {
  const AssetUnavailable([this.appleMessage]) : super('ASSET_UNAVAILABLE');

  final String? appleMessage;
}

/// The app has left the store and Apple turned down the requests that bring
/// it back for this account (an empty 403, a failed fallback) without saying
/// why. Not a final "no": the same request may pass later.
class RedownloadRefused extends AppError {
  const RedownloadRefused() : super('REDOWNLOAD_REFUSED');
}

class VersionUnavailable extends AppError {
  const VersionUnavailable() : super('VERSION_UNAVAILABLE');
}

class NetworkInterrupted extends AppError {
  const NetworkInterrupted([this.cause]) : super('TRANSFER_INTERRUPTED');

  /// Masked text of the failure, for the log.
  final String? cause;

  @override
  String? get logDetails => cause;
}

class PackageInvalid extends AppError {
  const PackageInvalid() : super('PACKAGE_INVALID');
}

class DiskFull extends AppError {
  const DiskFull() : super('DISK_FULL');
}

// --- Device and install -----------------------------------------------------

class DeviceNotFound extends AppError {
  const DeviceNotFound() : super('DEVICE_NOT_FOUND');
}

class DeviceNotTrusted extends AppError {
  const DeviceNotTrusted() : super('PAIRING_REQUIRED');
}

class DeviceLocked extends AppError {
  const DeviceLocked() : super('DEVICE_LOCKED');
}

class DriverMissing extends AppError {
  const DriverMissing() : super('DRIVER_MISSING');
}

class InsufficientSpace extends AppError {
  const InsufficientSpace() : super('DEVICE_STORAGE_FULL');
}

class IncompatibleOS extends AppError {
  const IncompatibleOS() : super('IOS_INCOMPATIBLE');
}

/// Another copy of the app (different source, or a pending App Store install)
/// is already on the device.
class InstallConflict extends AppError {
  const InstallConflict() : super('INSTALL_CONFLICT');
}

class InstallRejected extends AppError {
  const InstallRejected() : super('INSTALL_REJECTED');
}

/// The transfer ended without a definite answer; the device must be checked
/// before any retry.
class InstallResultUnknown extends AppError {
  const InstallResultUnknown() : super('INSTALL_RESULT_UNKNOWN');
}

// --- General ----------------------------------------------------------------

/// A bundled CLI is missing or cannot be started.
class ComponentMissing extends AppError {
  const ComponentMissing(this.component) : super('COMPONENT_MISSING');

  final String component;
}

class Cancelled extends AppError {
  const Cancelled() : super('CANCELLED');
}

/// Anything we could not classify. [safeDetails] is already masked.
class Unclassified extends AppError {
  const Unclassified(this.safeDetails) : super('UNCLASSIFIED');

  final String safeDetails;

  @override
  String? get logDetails => safeDetails;
}
