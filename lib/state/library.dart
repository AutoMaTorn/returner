import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/package_store.dart';
import 'operations.dart';
import 'providers.dart';

/// Packages in the local library, newest first. Re-read whenever an
/// operation changes stage, since finished downloads add packages.
final libraryProvider = NotifierProvider<LibraryController, List<Package>>(
  LibraryController.new,
);

class LibraryController extends Notifier<List<Package>> {
  @override
  List<Package> build() {
    ref.watch(
      operationsProvider.select(
        (operations) => [for (final o in operations) o.package?.id].join(','),
      ),
    );
    return ref.watch(packageStoreProvider).list();
  }

  Future<void> remove(String id) async {
    await ref.read(packageStoreProvider).remove(id);
    ref.invalidateSelf();
  }

  /// Copies a package to a place the user picked. The library copy stays.
  Future<void> export(Package package, String destination) =>
      File(package.path).copy(destination);
}

/// File name offered when exporting a package.
String exportFileName(Package package) {
  final name = package.info.displayName.replaceAll(
    RegExp(r'[\\/:*?"<>|]'),
    '_',
  );
  final version = package.info.displayVersion;
  return version == null ? '$name.ipa' : '$name $version.ipa';
}
