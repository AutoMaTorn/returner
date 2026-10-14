import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Layout of the app data directory. Nothing is stored next to the executable.
class AppPaths {
  const AppPaths(this.root);

  /// Resolves the per-user application support directory.
  static Future<AppPaths> resolve() async {
    final directory = await getApplicationSupportDirectory();
    return AppPaths(directory.path);
  }

  final String root;

  /// ipatool session (`IPATOOL_STATE_DIR`). Contents are secret.
  String get ipatoolState => p.join(root, 'ipatool');

  String get database => p.join(root, 'returner.db');

  /// Verified `.ipa` files, named by package id.
  String get library => p.join(root, 'library');

  String get staging => p.join(root, 'staging');

  String get logs => p.join(root, 'logs');

  /// Partial files of one operation.
  String stagingFor(String operationId) => p.join(staging, operationId);

  Future<void> ensure() async {
    for (final directory in [ipatoolState, library, staging, logs]) {
      await Directory(directory).create(recursive: true);
    }
  }
}
