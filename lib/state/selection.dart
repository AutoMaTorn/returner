import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ref.dart';
import '../services/package_store.dart';

/// Sections of the main screen.
enum HomeSection { catalog, search, files, settings }

final homeSectionProvider =
    NotifierProvider<HomeSectionController, HomeSection>(
      HomeSectionController.new,
    );

class HomeSectionController extends Notifier<HomeSection> {
  @override
  HomeSection build() => HomeSection.catalog;

  void show(HomeSection section) => state = section;
}

/// What the install panel is showing: an app from the store or a package
/// from the library.
class Selection {
  const Selection.app(
    AppRef this.app, {
    required this.title,
    this.details,
    this.versionLabel,
  }) : package = null;

  Selection.package(Package this.package)
    : app = null,
      title = package.info.displayName,
      details = null,
      versionLabel = null;

  final AppRef? app;
  final Package? package;
  final String title;

  /// Short line under the title, for example the name in the store.
  final String? details;

  /// Human version of the pinned build, when the user looked it up.
  final String? versionLabel;

  /// Key shared with operations on the same app.
  String get key => app?.key ?? package!.appStoreId ?? package!.info.bundleId;
}

final selectionProvider = NotifierProvider<SelectionController, Selection?>(
  SelectionController.new,
);

class SelectionController extends Notifier<Selection?> {
  @override
  Selection? build() => null;

  void select(Selection? selection) => state = selection;
}
