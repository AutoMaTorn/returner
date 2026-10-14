import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/errors.dart';

/// Minimal key-value view of the OS credential store.
abstract class SecretsBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Keychain on macOS, Credential Manager (DPAPI) on Windows.
class PlatformSecretsBackend implements SecretsBackend {
  const PlatformSecretsBackend();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Holds the only secret the app itself keeps: the passphrase that protects
/// ipatool's saved session. The Apple ID password is never stored.
class SecureStore {
  SecureStore(this._backend, {Random? random})
    : _random = random ?? Random.secure();

  static const _passphraseKey = 'ipatool-keychain-passphrase';

  final SecretsBackend _backend;
  final Random _random;
  String? _cached;

  /// Returns the passphrase, creating it on first use.
  ///
  /// Throws [StorageLocked] if the credential store cannot be used; there is
  /// deliberately no plain-text fallback.
  Future<String> keychainPassphrase() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      var value = await _backend.read(_passphraseKey);
      if (value == null || value.isEmpty) {
        value = base64.encode(
          List<int>.generate(32, (_) => _random.nextInt(256)),
        );
        await _backend.write(_passphraseKey, value);
        // Read back: a store that silently drops writes would lock the user
        // out of the session on the next launch.
        if (await _backend.read(_passphraseKey) != value) {
          throw const StorageLocked();
        }
      }
      return _cached = value;
    } on AppError {
      rethrow;
    } catch (_) {
      throw const StorageLocked();
    }
  }
}
