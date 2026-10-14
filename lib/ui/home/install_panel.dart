import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/package_store.dart';
import '../../state/devices.dart';
import '../../state/library.dart';
import '../../state/operations.dart';
import '../../state/selection.dart';
import '../../theme/am_widgets.dart';
import '../../theme/automatorn_theme.dart';
import '../strings.dart';
import '../widgets/app_widgets.dart';
import 'version_picker.dart';

/// Asks where to save a file; returns null if the user cancelled. Replaced
/// in tests.
final saveLocationProvider =
    Provider<Future<String?> Function(String suggestedName)>(
      (ref) => (suggestedName) async {
        final location = await getSaveLocation(
          suggestedName: suggestedName,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'ipa', extensions: ['ipa']),
          ],
        );
        return location?.path;
      },
    );

/// The right-hand panel: what is selected, the one main action, and how the
/// work on it is going. Replaces a separate "tasks" screen.
class InstallPanel extends ConsumerWidget {
  const InstallPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionProvider);
    return AmPanel(
      title: S.panelLabel,
      child: selection == null
          ? const AmEmptyState(label: S.panelEmptyLabel, text: S.panelEmpty)
          : _Selected(selection),
    );
  }
}

class _Selected extends ConsumerWidget {
  const _Selected(this.selection);

  final Selection selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.am;
    final device = ref.watch(currentDeviceProvider);
    final operation = ref
        .watch(operationsProvider)
        .where((o) => o.app.key == selection.key)
        .lastOrNull;
    final running = operation != null && !operation.stage.isTerminal;
    final controller = ref.read(operationsProvider.notifier);
    final package = selection.package;
    final app = selection.app;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(selection.title, style: Automatorn.prose.copyWith(color: c.ink)),
        if (selection.details != null)
          Text(
            selection.details!,
            style: Automatorn.caption.copyWith(color: c.muted),
          ),
        const SizedBox(height: 12),
        AmKeyValue({
          if (app?.appStoreId != null) S.kvId: app!.appStoreId!,
          if (app?.bundleId != null) S.kvBundle: app!.bundleId!,
          if (app?.externalVersionId != null)
            S.kvPinned: S.pinnedVersion(
              app!.externalVersionId!,
              selection.versionLabel,
            ),
          if (package != null) ...{
            if (package.appStoreId != null) S.kvId: package.appStoreId!,
            S.kvBundle: package.info.bundleId,
            if (package.info.displayVersion != null)
              S.kvVersion: package.info.displayVersion!,
            S.kvSize: S.megabytes(package.info.size),
            if (package.info.minimumOS != null)
              S.kvMinOs: package.info.minimumOS!,
            S.kvSha: package.info.sha256,
          },
        }, labelWidth: 96),
        const SizedBox(height: AmSize.formGap),
        if (running)
          OperationProgress(operation)
        else ...[
          if (operation != null) ...[
            OperationResult(
              operation,
              onPickVersion: app == null
                  ? null
                  : () => _pickVersion(context, ref, startInstall: true),
            ),
            const SizedBox(height: AmSize.formGap),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // The one primary action of the screen.
              FilledButton(
                onPressed: device == null
                    ? null
                    : () => package != null
                          ? controller.startInstall(package, device.udid)
                          : controller.start(
                              app!,
                              title: selection.title,
                              deviceUdid: device.udid,
                            ),
                child: const Text(S.actionInstall),
              ),
              if (app != null) ...[
                OutlinedButton(
                  onPressed: () =>
                      controller.start(app, title: selection.title),
                  child: const Text(S.actionDownload),
                ),
                OutlinedButton(
                  onPressed: () => _pickVersion(context, ref),
                  child: const Text(S.actionPickVersion),
                ),
              ],
              if (package != null) ...[
                OutlinedButton(
                  onPressed: () => _export(context, ref, package),
                  child: const Text(S.actionExport),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.danger,
                    side: BorderSide(color: c.danger),
                  ),
                  onPressed: () => _remove(context, ref, package),
                  child: const Text(S.actionRemove),
                ),
              ],
            ],
          ),
          if (device == null) ...[
            const SizedBox(height: 8),
            // A disabled control always says why.
            Text(
              S.needDevice,
              style: Automatorn.caption.copyWith(color: c.muted),
            ),
          ],
        ],
      ],
    );
  }

  /// Pins another build of the selected app. With [startInstall] the
  /// install starts again right away, on the same device.
  Future<void> _pickVersion(
    BuildContext context,
    WidgetRef ref, {
    bool startInstall = false,
  }) async {
    final app = selection.app!;
    final choice = await showVersionPicker(context, app);
    if (choice == null) return;
    final pinned = app.withVersion(choice.externalVersionId);
    ref
        .read(selectionProvider.notifier)
        .select(
          Selection.app(
            pinned,
            title: selection.title,
            details: selection.details,
            versionLabel: choice.displayVersion,
          ),
        );
    final device = ref.read(currentDeviceProvider);
    if (startInstall && device != null && choice.externalVersionId != null) {
      ref
          .read(operationsProvider.notifier)
          .start(pinned, title: selection.title, deviceUdid: device.udid);
    }
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    Package package,
  ) async {
    final path = await ref.read(saveLocationProvider)(exportFileName(package));
    if (path == null) return;
    await ref.read(libraryProvider.notifier).export(package, path);
    if (context.mounted) {
      showAmToast(context, S.exported, tone: AmTone.success);
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    Package package,
  ) async {
    final c = context.am;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(S.removeTitle),
        content: const Text(S.removeBody),
        actions: [
          AmGhostButton(
            label: S.cancel,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: c.danger,
              side: BorderSide(color: c.danger),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(S.actionRemove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(libraryProvider.notifier).remove(package.id);
    ref.read(selectionProvider.notifier).select(null);
    if (context.mounted) showAmToast(context, S.removed);
  }
}
