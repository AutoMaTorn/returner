import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../services/driver_service.dart';
import '../../state/devices.dart';
import '../../state/operations.dart';
import '../../state/selection.dart';
import '../../state/settings.dart';
import '../../theme/am_widgets.dart';
import '../../theme/automatorn_theme.dart';
import '../strings.dart';

/// Opens a link in the system handler. Replaced in tests.
final urlOpenerProvider = Provider<Future<void> Function(String url)>(
  (ref) =>
      (url) => launchUrl(Uri.parse(url)),
);

/// App Store icon in the list item's 32px lead slot. While it loads, and for
/// apps the store no longer knows, an empty framed square stands in.
class AppAvatar extends ConsumerWidget {
  const AppAvatar(this.appStoreId, {super.key, this.selected = false});

  final String? appStoreId;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.am;
    final id = appStoreId;
    final file = id == null ? null : ref.watch(appIconProvider(id)).value;
    final bundled =
        id != null &&
        (ref.watch(bundledIconsProvider).value?.contains(id) ?? false);
    final placeholder = Center(
      child: AmIcon('file', color: selected ? c.ink : c.muted),
    );
    return Container(
      width: AmSize.controlHeight,
      height: AmSize.controlHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: selected ? c.ink : c.rule),
        borderRadius: BorderRadius.circular(AmSize.radiusAvatar),
      ),
      // Order of trust: the icon from the store or from the downloaded
      // package, then the one shipped with the catalog, then a placeholder.
      child: file != null
          ? Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (context, _, _) => placeholder,
            )
          : bundled
          ? Image.asset(
              '$bundledIconPrefix$id.png',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, _, _) => placeholder,
            )
          : placeholder,
    );
  }
}

/// List item of the system with an app icon in the lead slot: title and one
/// line of details, a trailing tag or date, rows divided by `ruleFaint`.
class AppListItem extends StatelessWidget {
  const AppListItem({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.appStoreId,
    this.trailing,
    this.selected = false,
  });

  final String title;
  final String? subtitle;
  final String? appStoreId;
  final Widget? trailing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.am;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        hoverColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? c.ruleFaint : null,
            border: Border(bottom: BorderSide(color: c.ruleFaint)),
          ),
          child: Row(
            children: [
              AppAvatar(appStoreId, selected: selected),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Automatorn.code.copyWith(color: c.ink),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Automatorn.caption.copyWith(
                          color: c.muted,
                          height: 16 / 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tag that sums up the latest operation on an app, for list rows.
class OperationTag extends ConsumerWidget {
  const OperationTag(this.appKey, {super.key});

  final String appKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operation = ref.watch(
      operationsProvider.select(
        (list) => list.where((o) => o.app.key == appKey).lastOrNull,
      ),
    );
    if (operation == null) return const SizedBox.shrink();
    return switch (operation.stage) {
      OperationStage.done =>
        operation.outcome == null
            ? const AmTag('скачано', tone: AmTone.success)
            : const AmTag('установлено', tone: AmTone.success),
      OperationStage.failed => const AmTag('ошибка', tone: AmTone.danger),
      OperationStage.unknown => const AmTag('неизвестно', tone: AmTone.warning),
      OperationStage.cancelled => const SizedBox.shrink(),
      _ => const AmTag('идёт'),
    };
  }
}

/// A running operation: what it is doing now, with a way to stop it.
class OperationProgress extends ConsumerWidget {
  const OperationProgress(this.operation, {super.key});

  final Operation operation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.am;
    final percent = operation.stage == OperationStage.installing
        ? operation.installPercent
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (percent == null)
          Row(
            children: [
              const AmSpinner(),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  S.runningStatus(operation),
                  style: Automatorn.code.copyWith(color: c.text),
                ),
              ),
            ],
          )
        else
          AmAsciiProgress(
            value: percent / 100,
            label: S.runningStatus(operation),
            width: 16,
          ),
        const SizedBox(height: 8),
        AmGhostButton(
          label: S.cancel,
          onPressed: () =>
              ref.read(operationsProvider.notifier).cancel(operation.id),
        ),
      ],
    );
  }
}

/// A finished operation: what happened, in words, and what can be done next.
class OperationResult extends ConsumerWidget {
  const OperationResult(this.operation, {super.key, this.onPickVersion});

  final Operation operation;

  /// Offered when the build does not suit the device's iOS.
  final VoidCallback? onPickVersion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(operationsProvider.notifier);
    final error = operation.error;
    final name = operation.title;
    final version = operation.package?.info.displayVersion;

    final (AmTone tone, String title, String body) = switch (operation.stage) {
      OperationStage.done => switch (operation.outcome) {
        null => (AmTone.success, S.doneDownloaded, S.doneDownloadedBody),
        InstallOutcome.confirmed => (
          AmTone.success,
          S.doneInstalled,
          S.installedBody(name, version),
        ),
        InstallOutcome.versionUnknown => (
          AmTone.warning,
          S.doneVersionUnknown,
          S.doneVersionUnknownBody,
        ),
        InstallOutcome.unverified => (
          AmTone.warning,
          S.doneUnverified,
          S.doneUnverifiedBody,
        ),
      },
      OperationStage.unknown => (
        AmTone.warning,
        S.resultUnknown,
        S.resultUnknownBody,
      ),
      OperationStage.cancelled => (
        AmTone.neutral,
        S.cancelled,
        S.cancelledBody,
      ),
      _ =>
        error is LicenseRequired
            ? (AmTone.warning, S.noLicense, S.noLicenseBody)
            : (
                AmTone.danger,
                S.failed,
                error == null
                    ? S.errorText(const Unclassified(''))
                    : S.errorText(error),
              ),
    };

    final Widget? action = switch (operation.stage) {
      OperationStage.done || OperationStage.cancelled => null,
      // Explicit consent, asked at the moment it is needed.
      _ when error is IncompatibleOS && onPickVersion != null => OutlinedButton(
        onPressed: onPickVersion,
        child: const Text(S.actionOlderVersion),
      ),
      _ when error is LicenseRequired => OutlinedButton(
        onPressed: () => controller.retry(operation.id, allowFreeLicense: true),
        child: const Text(S.actionGetLicense),
      ),
      _ => OutlinedButton(
        onPressed: () => controller.retry(operation.id),
        child: const Text(S.retry),
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AmNotice(tone: tone, title: title, body: body),
        if (action != null) ...[const SizedBox(height: 12), action],
        // A failure can be reported without retyping anything.
        if (operation.stage == OperationStage.failed ||
            operation.stage == OperationStage.unknown)
          AmGhostButton(
            label: S.copyReport,
            small: true,
            onPressed: () => copyReport(context, ref),
          ),
      ],
    );
  }
}

/// Puts the masked report on the clipboard and says so.
Future<void> copyReport(BuildContext context, WidgetRef ref) async {
  final report = ref.read(reportProvider)();
  await Clipboard.setData(ClipboardData(text: report));
  if (context.mounted) {
    showAmToast(context, S.reportCopied, tone: AmTone.success);
  }
}

/// Points at a task that runs for an app other than the selected one, so
/// progress is never out of sight without a separate "tasks" screen.
class ActivityStrip extends ConsumerWidget {
  const ActivityStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.am;
    final running = ref
        .watch(operationsProvider)
        .where((o) => !o.stage.isTerminal)
        .firstOrNull;
    final selected = ref.watch(selectionProvider)?.key;
    if (running == null || running.app.key == selected) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          const AmLabel(S.activityLabel),
          const SizedBox(width: 12),
          const AmSpinner(),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${running.title} — ${S.runningStatus(running)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Automatorn.code.copyWith(color: c.text),
            ),
          ),
          AmGhostButton(
            label: S.activityShow,
            small: true,
            onPressed: () => ref
                .read(selectionProvider.notifier)
                .select(Selection.app(running.app, title: running.title)),
          ),
        ],
      ),
    );
  }
}

/// Things that block installing and can be fixed here: a missing Apple
/// driver, or several iPhones with none chosen.
class DeviceNotices extends ConsumerWidget {
  const DeviceNotices({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(driverMissingProvider)) return const _DriverNotice();
    final devices = ref.watch(devicesProvider).value ?? const [];
    if (devices.length < 2 || ref.watch(currentDeviceProvider) != null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AmNotice(title: S.severalTitle, body: S.severalBody),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final device in devices)
                OutlinedButton(
                  onPressed: () => ref
                      .read(selectedUdidProvider.notifier)
                      .select(device.udid),
                  child: Text(device.name),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DriverNotice extends ConsumerWidget {
  const _DriverNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.am;
    final state = ref.watch(driverInstallProvider);
    final install = ref.read(driverInstallProvider.notifier).install;
    final open = ref.read(urlOpenerProvider);
    final failed = state.status == DriverInstallStatus.failed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AmNotice(
            tone: failed ? AmTone.danger : AmTone.warning,
            title: failed ? S.driverFailedTitle : S.driverTitle,
            body: failed ? S.driverFailedBody : S.driverBody,
          ),
          const SizedBox(height: 12),
          if (state.status == DriverInstallStatus.installing)
            Row(
              children: [
                const AmSpinner(),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    state.message ?? S.driverInstalling,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Automatorn.code.copyWith(color: c.text),
                  ),
                ),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Runs only on this click, never on its own.
                OutlinedButton(
                  onPressed: install,
                  child: Text(failed ? S.retry : S.driverInstall),
                ),
                if (failed) ...[
                  OutlinedButton(
                    onPressed: () => open(DriverService.storeUri),
                    child: const Text(S.driverOpenStore),
                  ),
                  OutlinedButton(
                    onPressed: () => open(DriverService.itunesUri),
                    child: const Text(S.driverItunes),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
