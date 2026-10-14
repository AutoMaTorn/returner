import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
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

  List<String>? _ids;
  AppError? _error;
  var _shown = _pageSize;
  final _known = <String, VersionMetadata>{};
  final _loading = <String>{};
  final _failed = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final repository = ref.read(versionsRepositoryProvider);
    try {
      final ids = await repository.list(widget.app);
      if (!mounted) return;
      setState(() {
        _ids = ids;
        for (final id in ids) {
          final cached = repository.cached(widget.app, id);
          if (cached != null) _known[id] = cached;
        }
      });
    } on AppError catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  /// One request at a time: each takes tens of seconds.
  Future<void> _resolve(String id) async {
    if (_loading.isNotEmpty) return;
    setState(() {
      _loading.add(id);
      _failed.remove(id);
    });
    try {
      final metadata = await ref
          .read(versionsRepositoryProvider)
          .metadata(widget.app, id);
      if (mounted) setState(() => _known[id] = metadata);
    } on AppError {
      if (mounted) setState(() => _failed.add(id));
    } finally {
      if (mounted) setState(() => _loading.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.am;
    final ids = _ids;
    final error = _error;

    final Widget body;
    if (error != null) {
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
    } else if (ids == null) {
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
          Text(
            S.versionsHint(ids.length),
            style: Automatorn.caption.copyWith(color: c.muted),
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
      trailing = const AmSpinner();
    } else {
      trailing = AmGhostButton(
        label: _failed.contains(id) ? S.versionsRetry : S.versionsResolve,
        small: true,
        // Off while another build is being resolved.
        onPressed: _loading.isEmpty ? () => _resolve(id) : null,
      );
    }
    return AmListItem(
      title: latest
          ? '${S.versionsBuild} $id · ${S.versionsNewest}'
          : '${S.versionsBuild} $id',
      trailing: trailing,
      onTap: () =>
          Navigator.of(context).pop(VersionChoice(id, known?.displayVersion)),
    );
  }
}
