import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import '../core/errors.dart';
import '../models/ipa_info.dart';
import 'plist.dart';

/// Validates a downloaded `.ipa` and reads what the app calls itself.
///
/// Nothing is decrypted or modified: only the ZIP structure, checksums and
/// the app's `Info.plist` are read.
class IpaInspector {
  const IpaInspector();

  // Only the app's own Info.plist: not PlugIns/, Frameworks/ or Watch/.
  static final _infoPlist = RegExp(r'^Payload/[^/]+\.app/Info\.plist$');
  static const _maxInfoPlistBytes = 16 * 1024 * 1024;
  static const _maxArtworkBytes = 4 * 1024 * 1024;

  /// Throws [PackageInvalid] if the file is not a sound App Store package.
  /// Runs in a separate isolate: large packages take seconds to verify.
  Future<IpaInfo> inspect(String path) => Isolate.run(() => _inspect(path));

  /// The store artwork Apple puts in the package root (`iTunesArtwork`), or
  /// null if there is none. Reads that one entry only.
  Future<Uint8List?> artwork(String path) => Isolate.run(() {
    try {
      final input = InputFileStream(path);
      try {
        final entry = ZipDecoder().decodeStream(input).find('iTunesArtwork');
        if (entry == null || !entry.isFile || entry.size > _maxArtworkBytes) {
          return null;
        }
        return entry.readBytes();
      } finally {
        input.closeSync();
      }
    } catch (_) {
      return null;
    }
  });

  static Future<IpaInfo> _inspect(String path) async {
    final file = File(path);
    try {
      final size = file.lengthSync();
      final digest = (await sha256.bind(file.openRead()).first).toString();
      final info = _readInfoPlist(path);

      final bundleId = info['CFBundleIdentifier'];
      if (bundleId is! String || bundleId.isEmpty) throw const PackageInvalid();
      String? text(String key) {
        final value = info[key];
        return value is String && value.isNotEmpty ? value : null;
      }

      return IpaInfo(
        bundleId: bundleId,
        displayName:
            text('CFBundleDisplayName') ?? text('CFBundleName') ?? bundleId,
        displayVersion: text('CFBundleShortVersionString'),
        bundleVersion: text('CFBundleVersion'),
        minimumOS: text('MinimumOSVersion'),
        sha256: digest,
        size: size,
      );
    } on AppError {
      rethrow;
    } catch (_) {
      // Truncated archive, HTML error page saved as .ipa, bad plist, ...
      throw const PackageInvalid();
    }
  }

  static Map<String, Object?> _readInfoPlist(String path) {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      Map<String, Object?>? info;
      var files = 0;
      for (final entry in archive) {
        if (!_isSafeName(entry.name)) throw const PackageInvalid();
        if (!entry.isFile) continue;
        files++;

        final isInfo = _infoPlist.hasMatch(entry.name);
        if (isInfo && entry.size > _maxInfoPlistBytes) {
          throw const PackageInvalid();
        }
        // Decompressing every entry is what proves the archive is complete.
        final bytes = entry.readBytes();
        if (bytes == null || bytes.length != entry.size) {
          throw const PackageInvalid();
        }
        final expected = entry.crc32;
        if (expected != null && getCrc32(bytes) != expected) {
          throw const PackageInvalid();
        }
        if (isInfo) {
          if (info != null) throw const PackageInvalid();
          final plist = parsePlist(bytes);
          if (plist is! Map<String, Object?>) throw const PackageInvalid();
          info = plist;
        }
        entry.closeSync();
      }
      if (files == 0 || info == null) throw const PackageInvalid();
      return info;
    } finally {
      input.closeSync();
    }
  }

  /// Rejects absolute paths and parent-directory escapes.
  static bool _isSafeName(String name) {
    if (name.isEmpty || name.startsWith('/') || name.contains('\\')) {
      return false;
    }
    if (RegExp(r'^[A-Za-z]:').hasMatch(name)) return false;
    return !name.split('/').contains('..');
  }
}
