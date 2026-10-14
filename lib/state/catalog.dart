import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../models/app_ref.dart';
import '../models/store.dart';
import 'auth.dart';
import 'providers.dart';

/// One store listing of a product. A product can have several: a re-release
/// gets a new App Store ID and often another name.
class CatalogRelease {
  const CatalogRelease({
    required this.appStoreId,
    this.bundleId,
    this.storeName,
  });

  final String appStoreId;
  final String? bundleId;

  /// Name of the listing in the store when it differs from the product.
  final String? storeName;

  AppRef get ref => AppRef(appStoreId: appStoreId, bundleId: bundleId);
}

class CatalogProduct {
  const CatalogProduct({
    required this.title,
    required this.category,
    required this.releases,
  });

  final String title;
  final String category;
  final List<CatalogRelease> releases;
}

/// Parses `assets/catalog.json`. There is deliberately no "available" flag:
/// availability depends on the account and the moment.
List<CatalogProduct> parseCatalog(String json) => [
  for (final product in (jsonDecode(json) as List).cast<Map<String, dynamic>>())
    CatalogProduct(
      title: product['title'] as String,
      category: (product['category'] as String?) ?? '',
      releases: [
        for (final release
            in (product['releases'] as List).cast<Map<String, dynamic>>())
          CatalogRelease(
            appStoreId: '${release['appStoreId']}',
            bundleId: release['bundleId'] as String?,
            storeName: release['storeName'] as String?,
          ),
      ],
    ),
];

final catalogProvider = FutureProvider<List<CatalogProduct>>(
  (ref) async =>
      parseCatalog(await rootBundle.loadString('assets/catalog.json')),
);

class SearchState {
  const SearchState({
    this.query = '',
    this.results,
    this.loading = false,
    this.error,
  });

  final String query;

  /// Null until a search has finished.
  final List<StoreApp>? results;
  final bool loading;
  final AppError? error;
}

final searchProvider = NotifierProvider<StoreSearchController, SearchState>(
  StoreSearchController.new,
);

/// Text search in the store. Finds only apps that still have a store page.
class StoreSearchController extends Notifier<SearchState> {
  var _request = 0;

  @override
  SearchState build() => const SearchState();

  Future<void> search(String query) async {
    final term = query.trim();
    if (term.isEmpty) {
      state = const SearchState();
      return;
    }
    final request = ++_request;
    state = SearchState(query: term, loading: true);
    try {
      final results = await ref.read(ipatoolServiceProvider).search(term);
      if (request != _request) return; // A newer search replaced this one.
      state = SearchState(query: term, results: results);
    } on AppError catch (error) {
      if (request != _request) return;
      if (error is AuthSessionExpired) {
        ref.read(authProvider.notifier).markExpired();
      }
      state = SearchState(query: term, error: error);
    }
  }
}
