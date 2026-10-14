import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ref.dart';
import '../../state/catalog.dart';
import '../../state/library.dart';
import '../../state/selection.dart';
import '../../theme/am_widgets.dart';
import '../../theme/automatorn_theme.dart';
import '../strings.dart';
import '../widgets/app_widgets.dart';

/// Known listings. A product may have several; each is a row of its own.
class CatalogPanel extends ConsumerStatefulWidget {
  const CatalogPanel({super.key});

  @override
  ConsumerState<CatalogPanel> createState() => _CatalogPanelState();
}

class _CatalogPanelState extends ConsumerState<CatalogPanel> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.am;
    final products = ref.watch(catalogProvider).value ?? const [];
    final selected = ref.watch(selectionProvider)?.key;
    final query = _filter.text.trim().toLowerCase();

    final rows = [
      for (final product in products)
        for (final release in product.releases)
          if (query.isEmpty ||
              product.title.toLowerCase().contains(query) ||
              (release.storeName?.toLowerCase().contains(query) ?? false) ||
              release.appStoreId.contains(query))
            (product: product, release: release),
    ];
    final total = products.fold(0, (sum, p) => sum + p.releases.length);

    return AmPanel(
      title: S.catalogLabel,
      action: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Text(
          query.isEmpty ? '$total' : '${rows.length} из $total',
          style: Automatorn.footer.copyWith(
            color: c.muted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _filter,
            autocorrect: false,
            style: Automatorn.code.copyWith(color: c.ink),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: S.catalogFilter,
              hintText: S.catalogFilterHint,
              prefixIcon: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: AmIcon('search'),
              ),
              prefixIconConstraints: BoxConstraints(minWidth: 32),
            ),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty && query.isNotEmpty)
            AmEmptyState(
              label: S.searchEmptyLabel,
              text: S.catalogEmpty(_filter.text.trim()),
              actions: [
                OutlinedButton(
                  onPressed: () => ref
                      .read(homeSectionProvider.notifier)
                      .show(HomeSection.search),
                  child: const Text(S.catalogOpenSearch),
                ),
              ],
            ),
          for (final row in rows)
            AppListItem(
              appStoreId: row.release.appStoreId,
              title: row.product.title,
              subtitle: [
                ?row.release.storeName,
                if (row.product.category.isNotEmpty)
                  row.product.category.toLowerCase(),
                'id ${row.release.appStoreId}',
              ].join(' · '),
              selected: selected == row.release.appStoreId,
              trailing: OperationTag(row.release.appStoreId),
              onTap: () => ref
                  .read(selectionProvider.notifier)
                  .select(
                    Selection.app(
                      row.release.ref,
                      title: row.product.title,
                      details: row.release.storeName == null
                          ? null
                          : '${S.kvStore}: ${row.release.storeName}',
                    ),
                  ),
            ),
        ],
      ),
    );
  }
}

/// One field for a name, an App Store ID or a store link. An ID or link
/// needs no store page: it is offered at once.
class SearchPanel extends ConsumerStatefulWidget {
  const SearchPanel({super.key});

  @override
  ConsumerState<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<SearchPanel> {
  late final _input = TextEditingController(
    text: ref.read(searchProvider).query,
  );

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// Bundle ids are left to the text search: only digits and links count.
  AppRef? get _direct {
    final parsed = AppRef.parse(_input.text);
    return parsed?.appStoreId == null ? null : parsed;
  }

  void _search() {
    if (_direct != null) return;
    ref.read(searchProvider.notifier).search(_input.text);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.am;
    final state = ref.watch(searchProvider);
    final selected = ref.watch(selectionProvider)?.key;
    final direct = _direct;
    final results = state.results;

    return AmPanel(
      title: S.searchLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  autofocus: true,
                  autocorrect: false,
                  style: Automatorn.code.copyWith(color: c.ink),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    labelText: S.searchField,
                    hintText: S.searchHint,
                    helperText: S.searchHelper,
                    helperMaxLines: 3,
                    prefixIcon: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: AmIcon('search'),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 32),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: direct == null && _input.text.trim().isNotEmpty
                    ? _search
                    : null,
                child: const Text(S.searchSubmit),
              ),
            ],
          ),
          if (direct != null) ...[
            const SizedBox(height: AmSize.formGap),
            const AmLabel(S.searchById),
            const SizedBox(height: 4),
            AppListItem(
              appStoreId: direct.appStoreId,
              title: 'App Store ID ${direct.appStoreId}',
              selected: selected == direct.appStoreId,
              trailing: OperationTag(direct.key),
              onTap: () => ref
                  .read(selectionProvider.notifier)
                  .select(
                    Selection.app(
                      direct,
                      title: 'App Store ID ${direct.appStoreId}',
                    ),
                  ),
            ),
          ] else if (state.loading) ...[
            const SizedBox(height: AmSize.formGap),
            Row(
              children: [
                const AmSpinner(),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    S.searchWorking,
                    style: Automatorn.code.copyWith(color: c.text),
                  ),
                ),
              ],
            ),
          ] else if (state.error != null) ...[
            const SizedBox(height: AmSize.formGap),
            AmNotice(
              tone: AmTone.danger,
              title: S.failed,
              body: S.errorText(state.error!),
            ),
          ] else if (results != null && results.isEmpty)
            AmEmptyState(
              label: S.searchEmptyLabel,
              text: S.searchEmpty(state.query),
            )
          else if (results != null) ...[
            const SizedBox(height: AmSize.formGap),
            const AmLabel(S.searchResults),
            const SizedBox(height: 4),
            for (final app in results)
              AppListItem(
                appStoreId: app.appStoreId,
                title: app.name,
                subtitle: [?app.version, 'id ${app.appStoreId}'].join(' · '),
                selected: selected == app.appStoreId,
                trailing: OperationTag(app.appStoreId),
                onTap: () => ref
                    .read(selectionProvider.notifier)
                    .select(
                      Selection.app(
                        AppRef(
                          appStoreId: app.appStoreId,
                          bundleId: app.bundleId,
                        ),
                        title: app.name,
                      ),
                    ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Downloaded packages. They install again without the network or a session.
class FilesPanel extends ConsumerWidget {
  const FilesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packages = ref.watch(libraryProvider);
    final selection = ref.watch(selectionProvider);
    return AmPanel(
      title: S.filesLabel,
      child: packages.isEmpty
          ? AmEmptyState(
              label: S.filesEmptyLabel,
              text: S.filesEmpty,
              actions: [
                OutlinedButton(
                  onPressed: () => ref
                      .read(homeSectionProvider.notifier)
                      .show(HomeSection.catalog),
                  child: const Text(S.filesOpenCatalog),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final package in packages)
                  AppListItem(
                    appStoreId: package.appStoreId,
                    title: package.info.displayName,
                    subtitle: [
                      ?package.info.displayVersion,
                      S.megabytes(package.info.size),
                    ].join(' · '),
                    selected: selection?.package?.id == package.id,
                    trailing: Text(
                      _date(package.finalizedAt),
                      style: Automatorn.meta.copyWith(
                        color: context.am.muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    onTap: () => ref
                        .read(selectionProvider.notifier)
                        .select(Selection.package(package)),
                  ),
              ],
            ),
    );
  }

  /// Table-style date: 13.10.2026.
  static String _date(DateTime date) =>
      '${'${date.day}'.padLeft(2, '0')}.${'${date.month}'.padLeft(2, '0')}.${date.year}';
}
