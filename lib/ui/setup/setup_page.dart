import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/errors.dart';
import '../../state/auth.dart';
import '../../state/operations.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';
import '../../theme/am_widgets.dart';
import '../../theme/automatorn_theme.dart';
import '../strings.dart';

/// First screen: what the app does, and a check that it can work.
class SetupPage extends ConsumerStatefulWidget {
  const SetupPage({super.key});

  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends ConsumerState<SetupPage> {
  var _ready = false;
  AppError? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  Future<void> _prepare() async {
    setState(() {
      _ready = false;
      _error = null;
    });
    try {
      // Fail early, with a clear message, if a bundled tool is missing.
      final binaries = ref.read(binariesProvider);
      binaries.ipatool;
      binaries.ios;
      // Applies the saved storefront before the first icon is requested.
      ref.read(lookupCountryProvider);
      await ref.read(operationsProvider.notifier).recover();
      await ref.read(authProvider.notifier).restore();
    } on AppError catch (error) {
      if (mounted) setState(() => _error = error);
      return;
    }
    if (mounted) setState(() => _ready = true);
  }

  void _continue() {
    final signedIn = ref.read(authProvider).status == AuthStatus.authenticated;
    Navigator.of(context)
        .pushReplacementNamed(signedIn ? Routes.home : Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.am;
    final error = _error;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 64),
          child: AmColumn(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.appName,
                    style: Automatorn.prose.copyWith(color: c.ink),
                  ),
                  const SizedBox(height: AmSize.gapCopy),
                  Text(
                    S.setupLead,
                    style: Automatorn.prose.copyWith(color: c.text),
                  ),
                  const SizedBox(height: AmSize.gapCopy),
                  Text(
                    S.setupHow,
                    style: Automatorn.prose.copyWith(color: c.text),
                  ),
                ],
              ),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AmLabel(S.setupStepsLabel),
                  SizedBox(height: 12),
                  AmListRow(
                    title: S.setupStepLogin,
                    meta: S.setupStepLoginMeta,
                  ),
                  AmListRow(
                    title: S.setupStepDevice,
                    meta: S.setupStepDeviceMeta,
                  ),
                  AmListRow(title: S.setupStepApp, meta: S.setupStepAppMeta),
                ],
              ),
              if (error != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AmNotice(
                      tone: AmTone.danger,
                      title: S.setupFailed,
                      body: S.errorText(error),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _prepare,
                      child: const Text(S.retry),
                    ),
                  ],
                )
              else if (!_ready)
                Row(
                  children: [
                    const AmSpinner(),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        S.setupChecking,
                        style: Automatorn.code.copyWith(color: c.text),
                      ),
                    ),
                  ],
                )
              else
                FilledButton(
                  onPressed: _continue,
                  child: const Text(S.setupContinue),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
