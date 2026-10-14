import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log.dart';
import '../../state/auth.dart';
import '../../state/devices.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';
import '../../theme/am_widgets.dart';
import '../../theme/automatorn_theme.dart';
import '../strings.dart';
import '../widgets/app_widgets.dart';

/// A reading screen: one column, sections under lowercase labels.
class SettingsSection extends ConsumerWidget {
  const SettingsSection({super.key});

  static const _upstream = {
    'ipatool': 'https://github.com/majd/ipatool',
    'go-ios': 'https://github.com/danielpaulus/go-ios',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.am;
    final account = ref.watch(authProvider).account;
    final device = ref.watch(currentDeviceProvider);
    final mode = ref.watch(themeModeProvider);
    final country = ref.watch(lookupCountryProvider);
    final open = ref.read(urlOpenerProvider);

    Widget section(String label, List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [AmLabel(label), const SizedBox(height: 12), ...children],
    );
    Widget note(String text) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, style: Automatorn.caption.copyWith(color: c.muted)),
    );

    return AmColumn(
      children: [
        section(S.settingsAccount, [
          AmKeyValue({
            S.navAccount: account == null ? S.accountNone : mask(account.email),
            S.navDevice: device == null
                ? S.deviceNone
                : '${device.name} · ${S.deviceOs(device.osVersion)}',
          }),
          if (account != null) ...[
            const SizedBox(height: AmSize.gapCopy),
            // Removes the saved session only; packages stay.
            OutlinedButton(
              onPressed: ref.read(authProvider.notifier).logout,
              child: const Text(S.settingsLogout),
            ),
            note(S.settingsLogoutNote),
          ],
        ]),
        section(S.settingsTheme, [
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.dark, label: Text(S.themeNight)),
              ButtonSegment(value: ThemeMode.light, label: Text(S.themePaper)),
            ],
            selected: {mode},
            onSelectionChanged: (selection) =>
                ref.read(themeModeProvider.notifier).set(selection.single),
          ),
        ]),
        section(S.settingsCountry, [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final code in lookupCountries)
                ButtonSegment(value: code, label: Text(code.toUpperCase())),
            ],
            selected: {country},
            onSelectionChanged: (selection) =>
                ref.read(lookupCountryProvider.notifier).set(selection.single),
          ),
          note(S.settingsCountryNote),
        ]),
        section(S.settingsLog, [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => copyReport(context, ref),
                child: const Text(S.copyReportButton),
              ),
              OutlinedButton(
                onPressed: () =>
                    open(Uri.file(ref.read(appPathsProvider).logs).toString()),
                child: const Text(S.openLogFolder),
              ),
            ],
          ),
          note(S.settingsLogNote),
        ]),
        section(S.settingsAbout, [
          const AmKeyValue({
            S.aboutVersion: appVersion,
            S.aboutEngine: 'ipatool $ipatoolVersion, go-ios $goIosVersion',
            S.aboutData: S.aboutDataValue,
          }),
          const SizedBox(height: AmSize.gapCopy),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => _showLicenses(context),
                child: const Text(S.aboutLicenses),
              ),
              for (final entry in _upstream.entries)
                AmBracketLink(
                  text: entry.key,
                  style: Automatorn.code,
                  onTap: () => open(entry.value),
                ),
            ],
          ),
        ]),
      ],
    );
  }

  /// Both bundled tools are MIT-licensed; ipatool ships modified, which the
  /// license asks us to say.
  static Future<void> _showLicenses(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => const _LicensesDialog(),
  );
}

class _LicensesDialog extends StatefulWidget {
  const _LicensesDialog();

  @override
  State<_LicensesDialog> createState() => _LicensesDialogState();
}

class _LicensesDialogState extends State<_LicensesDialog> {
  static const _files = {
    'ipatool': 'licenses/ipatool-LICENSE.txt',
    'go-ios': 'licenses/go-ios-LICENSE.txt',
  };

  // The note about the modified build is shown at once; the texts follow.
  late final Future<List<String>> _texts = Future.wait([
    for (final path in _files.values) rootBundle.loadString(path),
  ]);

  @override
  Widget build(BuildContext context) {
    final c = context.am;
    return AlertDialog(
      title: const Text(S.aboutLicensesTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: FutureBuilder<List<String>>(
            future: _texts,
            builder: (context, snapshot) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.aboutPatched,
                  style: Automatorn.code.copyWith(color: c.text),
                ),
                for (final (index, name) in _files.keys.indexed) ...[
                  const SizedBox(height: AmSize.formGap),
                  AmLabel(name),
                  const SizedBox(height: 8),
                  if (snapshot.hasData)
                    SelectableText(
                      snapshot.data![index].trim(),
                      style: Automatorn.caption.copyWith(color: c.muted),
                    )
                  else if (snapshot.hasError)
                    Text(
                      'MIT License',
                      style: Automatorn.caption.copyWith(color: c.muted),
                    )
                  else
                    const AmSpinner(),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        AmGhostButton(
          label: S.aboutClose,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
