import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/log.dart';
import '../../models/app_ref.dart';
import '../../models/store.dart';
import '../../state/versions.dart';
import '../../theme/am_widgets.dart';
import '../../theme/automatorn_theme.dart';
import '../strings.dart';

/// Result of the picker: a build to pin, or "back to the latest".
class VersionChoice {
  const VersionChoice(this.externalVersionId, [this.displayVersion]);

  /// Null means the latest version.
  final String? externalVersionId;
  final String? displayVersion;
}

/// Lets the user pin an older build. Returns null when dismissed.
Future<VersionChoice?> showVersionPicker(BuildContext context, AppRef app) =>
    showDialog<VersionChoice>(
      context: context,
      builder: (context) => _VersionPicker(app),
    );

class _VersionPicker extends ConsumerStatefulWidget {
  const _VersionPicker(this.app);

  final AppRef app;

  @override
  ConsumerState<_VersionPicker> createState() => _VersionPickerState();
}

class _VersionPickerState extends ConsumerState<_VersionPicker> {
  static const _pageSize = 30;

  VersionList? _list;
  AppError? _error;
  var _refreshing = false;
  var _shown = _pageSize;
  final _known = <String, VersionMetadata>{};
  final _loading = <String>{};
  final _failed = <String, AppError>{};

  /// The last build lookup that failed, shown above the list.
  AppError? _lookupError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Opens with the saved list when there is one; [refresh] asks Apple.
  /// A failed refresh leaves the saved list on screen.
  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _error = null;
      _refreshing = refresh;
    });
    final repository = ref.read(versionsRepositoryProvider);
    try {
      final list = await repository.list(widget.app, refresh: refresh);
      if (!mounted) return;
      setState(() {
        _list = list;
        for (final id in list.ids) {
          final cached = repository.cached(widget.app, id);
          if (cached != null) _known[id] = cached;
        }
      });
    } on AppError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// One request at a time: each takes tens of seconds.
  Future<void> _resolve(String id) async {
    if (_loading.isNotEmpty) return;
    setState(() {
      _loading.add(id);
      _failed.remove(id);
      _lookupError = null;
    });
    final watch = Stopwatch()..start();
    try {
      final metadata = await ref
          .read(versionsRepositoryProvider)
          .metadata(widget.app, id);
      Log.info('Version lookup took ${watch.elapsed.inSeconds} s');
      if (mounted) setState(() => _known[id] = metadata);
    } on AppError catch (error) {
      Log.warning(
        'Version lookup failed after ${watch.elapsed.inSeconds} s: '
        '${error.code}'
        '${error.logDetails == null ? '' : ' ${error.logDetails}'}',
      );
      if (mounted) {
        setState(() {
          _failed[id] = error;
          _lookupError = error;
        });
      }
    } finally {
      if (mounted) setState(() => _loading.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.am;
    final list = _list;
    final ids = list?.ids;
    final error = _error;

    final Widget body;
    if (error != null && list == null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AmNotice(
            tone: AmTone.danger,
            title: S.versionsFailed,
            body: S.errorText(error),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: const Text(S.retry)),
        ],
      );
    } else if (ids == null || _refreshing) {
      body = Row(
        children: [
          const AmSpinner(),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              S.versionsLoading,
              style: Automatorn.code.copyWith(color: c.text),
            ),
          ),
        ],
      );
    } else {
      final visible = ids.take(_shown).toList();
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null) ...[
            AmNotice(
              tone: AmTone.danger,
              title: S.versionsRefreshFailed,
              body: S.errorText(error),
            ),
            const SizedBox(height: 12),
          ],
          if (_lookupError != null) ...[
            AmNotice(
              tone: AmTone.danger,
              title: S.versionsLookupFailed,
              body: S.errorText(_lookupError!),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            S.versionsHint(ids.length),
            style: Automatorn.caption.copyWith(color: c.muted),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  S.versionsFetched(list!.fetchedAt),
                  style: Automatorn.meta.copyWith(color: c.muted),
                ),
              ),
              AmGhostButton(
                label: S.versionsRefresh,
                small: true,
                // A refresh would race a build lookup for the same session.
                onPressed: _loading.isEmpty ? () => _load(refresh: true) : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final id in visible) _row(c, id, id == ids.first),
                if (ids.length > _shown)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AmGhostButton(
                      label: S.versionsMore,
                      onPressed: () => setState(() => _shown += _pageSize),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text(S.versionsTitle),
      content: SizedBox(width: 440, child: body),
      actions: [
        AmGhostButton(
          label: S.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(const VersionChoice(null)),
          child: const Text(S.versionsLatest),
        ),
      ],
    );
  }

  Widget _row(AmColors c, String id, bool latest) {
    final known = _known[id];
    final date = known?.releaseDate;
    final Widget trailing;
    if (known != null) {
      trailing = Text(
        date == null
            ? known.displayVersion
            : '${known.displayVersion} · ${S.shortDate(date)}',
        style: Automatorn.meta.copyWith(
          color: c.ink,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    } else if (_loading.contains(id)) {
      trailing = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [_Elapsed(), SizedBox(width: 8), AmSpinner()],
      );
    } else {
      trailing = AmGhostButton(
        label: _failed.containsKey(id) ? S.versionsRetry : S.versionsResolve,
        small: true,
        // Off while another build is being resolved.
        onPressed: _loading.isEmpty ? () => _resolve(id) : null,
      );
    }
    return AmListItem(
      title: latest
          ? '${S.versionsBuild} $id · ${S.versionsNewest}'
          : '${S.versionsBuild} $id',
      subtitle: _failed.containsKey(id) ? S.versionsLookupFailedShort : null,
      trailing: trailing,
      onTap: () =>
          Navigator.of(context).pop(VersionChoice(id, known?.displayVersion)),
    );
  }
}

/// Seconds since it appeared: a build lookup takes tens of seconds, and a
/// counting number shows it is still going.
class _Elapsed extends StatefulWidget {
  const _Elapsed();

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  final _watch = Stopwatch()..start();
  late final Timer _timer = Timer.periodic(
    const Duration(seconds: 1),
    (_) => setState(() {}),
  );

  @override
  void initState() {
    super.initState();
    _timer; // Start ticking.
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    S.seconds(_watch.elapsed.inSeconds),
    style: Automatorn.meta.copyWith(
      color: context.am.muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}
