import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../data/auth_api.dart';
import '../data/auth_repository.dart';
import '../domain/session.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(AuthApi(ref.watch(apiClientProvider)), ref.watch(tokenStoreProvider)),
);

/// Why the user is looking at the sign-in screen (e.g. "session expired"), shown once.
final signInNoticeProvider = NotifierProvider<SignInNotice, String?>(SignInNotice.new);

class SignInNotice extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String message) => state = message;

  void clear() => state = null;
}

/// The app-wide session. `null` = signed out. The router redirects on every change.
final sessionControllerProvider = AsyncNotifierProvider<SessionController, Session?>(SessionController.new);

class SessionController extends AsyncNotifier<Session?> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<Session?> build() async {
    ref.read(apiClientProvider).onSessionExpired = () => unawaited(expire());

    final cached = await _repo.restore();
    if (cached != null) {
      unawaited(_revalidate()); // offline-first: open immediately, refresh in the background
    }
    return cached;
  }

  /// Throws [ApiException] on failure so the sign-in form can show field errors.
  Future<void> signIn(String email, String password) async {
    final session = await _repo.signIn(email, password);
    ref.read(signInNoticeProvider.notifier).clear();
    state = AsyncData(session);
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = const AsyncData(null);
  }

  Future<int> signOutEverywhere() async {
    final count = await _repo.signOutEverywhere();
    state = const AsyncData(null);
    return count;
  }

  /// The refresh token was rejected (expired, revoked or reused): back to sign-in.
  Future<void> expire() async {
    if (state.value == null) return;
    await _repo.clearLocal();
    ref.read(signInNoticeProvider.notifier).show('Your session has ended. Please sign in again.');
    state = const AsyncData(null);
  }

  Future<void> updateProfile({required String fullName, String? phone}) async {
    state = AsyncData(await _repo.updateProfile(fullName: fullName, phone: phone));
  }

  Future<void> _revalidate() async {
    try {
      final fresh = await _repo.refreshProfile();
      if (state.value != null) state = AsyncData(fresh);
    } on UnauthorizedException {
      await expire();
    } on ForbiddenException {
      await expire(); // account deactivated
    } on ApiException {
      // Offline or server unavailable: keep working with the cached session.
    }
  }
}
