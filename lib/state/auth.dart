import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cancel.dart';
import '../core/errors.dart';
import '../core/log.dart';
import '../models/store.dart';
import 'providers.dart';

enum AuthStatus {
  /// The saved session has not been checked yet.
  unknown,
  signedOut,
  signingIn,
  waitingForCode,
  authenticated,
  expired,
  storageLocked,
}

class AuthState {
  const AuthState(this.status, {this.account, this.error});

  final AuthStatus status;
  final AccountInfo? account;

  /// Why the last sign-in step failed, if it did.
  final AppError? error;

  bool get isBusy => status == AuthStatus.signingIn;

  /// Stable, non-reversible id of the account for local records.
  String? get accountId =>
      account == null ? null : accountIdFor(account!.email);
}

String accountIdFor(String email) => sha256
    .convert(utf8.encode(email.trim().toLowerCase()))
    .toString()
    .substring(0, 16);

final authProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  /// Credentials kept in memory only while Apple waits for a 2FA code.
  ({String email, String password})? _pending;
  CancelToken? _cancel;

  @override
  AuthState build() => const AuthState(AuthStatus.unknown);

  /// Checks for a saved session on startup.
  Future<void> restore() async {
    try {
      final account = await ref.read(ipatoolServiceProvider).currentAccount();
      state = account == null
          ? const AuthState(AuthStatus.signedOut)
          : AuthState(AuthStatus.authenticated, account: account);
    } on StorageLocked catch (error) {
      state = AuthState(AuthStatus.storageLocked, error: error);
    } on AppError catch (error) {
      Log.warning('Session check failed: ${error.code}');
      state = AuthState(AuthStatus.signedOut, error: error);
    }
  }

  Future<void> login(String email, String password) =>
      _signIn(email.trim(), password, null);

  /// Completes a sign-in that is waiting for a 2FA code.
  Future<void> submitCode(String code) async {
    final pending = _pending;
    if (pending == null) {
      state = const AuthState(AuthStatus.signedOut);
      return;
    }
    await _signIn(pending.email, pending.password, code.trim());
  }

  Future<void> _signIn(String email, String password, String? code) async {
    if (state.isBusy) return;
    final cancel = _cancel = CancelToken();
    state = const AuthState(AuthStatus.signingIn);
    try {
      final account = await ref
          .read(ipatoolServiceProvider)
          .login(email, password, code: code, cancel: cancel);
      _pending = null;
      state = AuthState(AuthStatus.authenticated, account: account);
    } on AuthNeeds2FA {
      _pending = (email: email, password: password);
      state = const AuthState(AuthStatus.waitingForCode);
    } on AuthInvalidCode catch (error) {
      // The code is single-use; the user asks for a new one and retries.
      state = AuthState(AuthStatus.waitingForCode, error: error);
    } on Cancelled {
      _pending = null;
      state = const AuthState(AuthStatus.signedOut);
    } on StorageLocked catch (error) {
      _pending = null;
      state = AuthState(AuthStatus.storageLocked, error: error);
    } on AppError catch (error) {
      _pending = null;
      state = AuthState(AuthStatus.signedOut, error: error);
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
    }
  }

  /// Aborts a running sign-in or leaves the 2FA step.
  void cancel() {
    _pending = null;
    final running = _cancel;
    if (running != null) {
      running.cancel();
    } else {
      state = const AuthState(AuthStatus.signedOut);
    }
  }

  /// Called by operations when Apple rejects the saved session.
  void markExpired() {
    _pending = null;
    state = const AuthState(AuthStatus.expired);
  }

  Future<void> logout() async {
    try {
      await ref.read(ipatoolServiceProvider).logout();
      state = const AuthState(AuthStatus.signedOut);
    } on AppError catch (error) {
      state = AuthState(state.status, account: state.account, error: error);
    }
  }
}
