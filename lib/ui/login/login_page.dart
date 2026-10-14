import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/errors.dart';
import '../../state/auth.dart';
import '../../theme/am_widgets.dart';
import '../../theme/automatorn_theme.dart';
import '../strings.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  String? _formError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _submitCredentials() {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _formError = S.loginFillBoth);
      return;
    }
    setState(() => _formError = null);
    // The password leaves this widget right away; the controller that keeps
    // it for a possible 2FA step is not part of any UI state.
    _password.clear();
    ref.read(authProvider.notifier).login(email, password);
  }

  void _submitCode() {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _formError = S.loginCodeHelper);
      return;
    }
    setState(() => _formError = null);
    _code.clear();
    ref.read(authProvider.notifier).submitCode(code);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated) {
        Navigator.of(context).pushReplacementNamed(Routes.home);
      }
    });
    final auth = ref.watch(authProvider);
    final c = context.am;
    final waitingForCode = auth.status == AuthStatus.waitingForCode;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 64),
          child: AmColumn(
            children: [
              Text(S.appName, style: Automatorn.prose.copyWith(color: c.ink)),
              // A form is narrower than a column of prose.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AmLabel(waitingForCode ? S.loginCodeTitle : S.loginTitle),
                    const SizedBox(height: AmSize.formGap),
                    ...switch (auth.status) {
                      AuthStatus.signingIn => _working(c),
                      AuthStatus.waitingForCode => _codeStep(c, auth.error),
                      _ => _credentials(c, auth),
                    },
                  ],
                ),
              ),
              Text(
                S.loginPrivacy,
                style: Automatorn.caption.copyWith(color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _credentials(AmColors c, AuthState auth) {
    final error = auth.error;
    return [
      if (auth.status == AuthStatus.expired && _formError == null) ...[
        const AmNotice(
          tone: AmTone.warning,
          title: S.loginTitle,
          body: S.loginExpired,
        ),
        const SizedBox(height: AmSize.formGap),
      ],
      if (error != null && _formError == null) ...[
        AmNotice(
          tone: AmTone.danger,
          title: S.loginFailed,
          body: S.errorText(error),
        ),
        const SizedBox(height: AmSize.formGap),
      ],
      TextField(
        controller: _email,
        autofocus: true,
        autocorrect: false,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        style: Automatorn.code.copyWith(color: c.ink),
        decoration: const InputDecoration(
          labelText: S.loginEmail,
          hintText: S.loginEmailHint,
        ),
      ),
      const SizedBox(height: AmSize.formGap),
      TextField(
        controller: _password,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        style: Automatorn.code.copyWith(color: c.ink),
        onSubmitted: (_) => _submitCredentials(),
        decoration: InputDecoration(
          labelText: S.loginPassword,
          errorText: _formError,
        ),
      ),
      const SizedBox(height: AmSize.formGap),
      FilledButton(
        onPressed: _submitCredentials,
        child: const Text(S.loginSubmit),
      ),
    ];
  }

  List<Widget> _working(AmColors c) => [
    Row(
      children: [
        const AmSpinner(),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            S.loginWorking,
            style: Automatorn.code.copyWith(color: c.text),
          ),
        ),
      ],
    ),
    const SizedBox(height: 8),
    Text(
      S.loginWorkingHint,
      style: Automatorn.caption.copyWith(color: c.muted),
    ),
    const SizedBox(height: AmSize.gapCopy),
    AmGhostButton(
      label: S.cancel,
      onPressed: ref.read(authProvider.notifier).cancel,
    ),
  ];

  List<Widget> _codeStep(AmColors c, AppError? error) => [
    TextField(
      controller: _code,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      style: Automatorn.code.copyWith(color: c.ink),
      onSubmitted: (_) => _submitCode(),
      decoration: InputDecoration(
        labelText: S.loginCodeField,
        hintText: '000000…',
        helperText: S.loginCodeHelper,
        helperMaxLines: 2,
        errorMaxLines: 3,
        errorText: _formError ?? (error == null ? null : S.errorText(error)),
      ),
    ),
    const SizedBox(height: AmSize.formGap),
    Row(
      children: [
        FilledButton(
          onPressed: _submitCode,
          child: const Text(S.loginCodeSubmit),
        ),
        const SizedBox(width: 8),
        AmGhostButton(
          label: S.cancel,
          onPressed: ref.read(authProvider.notifier).cancel,
        ),
      ],
    ),
  ];
}
