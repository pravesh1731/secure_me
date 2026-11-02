import 'dart:async';

import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../crypto/key_backup.dart';
import '../crypto/keygen.dart';
import '../crypto/rsa_keys.dart';
import 'directory_service.dart';
import 'local_key_store.dart';

enum SessionStatus {
  loading,
  signedOut,

  /// Signed in, but the private key isn't available on this device yet.
  locked,
  ready,
}

/// App-wide auth + key state. The private key never leaves the device
/// unencrypted: it lives in secure storage locally and in Firestore only as
/// a password-wrapped backup.
class Session extends ChangeNotifier {
  Session({FirebaseAuth? auth, DirectoryService? directory, LocalKeyStore? keys})
      : _auth = auth ?? FirebaseAuth.instance,
        directory = directory ?? DirectoryService(),
        _keys = keys ?? LocalKeyStore();

  final FirebaseAuth _auth;
  final DirectoryService directory;
  final LocalKeyStore _keys;

  SessionStatus status = SessionStatus.loading;
  User? user;
  RsaIdentity? identity;

  /// Set while locked when the backup didn't open with the account password
  /// (typically after a password reset by email).
  bool backupPasswordMismatch = false;

  /// Non-null while a long operation (key generation, PBKDF2) is running.
  String? busyMessage;

  StreamSubscription<User?>? _authSub;

  String get displayName {
    final name = user?.displayName ?? '';
    return name.isNotEmpty ? name : (user?.email ?? '');
  }

  Future<void> init() async {
    final current = await _auth.authStateChanges().first;
    _authSub = _auth.authStateChanges().skip(1).listen((u) {
      if (u == null && status != SessionStatus.signedOut) _reset();
    });
    if (current == null) return _reset();
    user = current;
    try {
      final local = await _keys.load(current.uid);
      if (local != null && await _matchesDirectory(current.uid, local)) {
        return _ready(local);
      }
    } catch (_) {
      // Fall through to the lock screen; unlocking will re-sync.
    }
    _lock();
  }

  Future<void> signUp({required String name, required String email, required String password}) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    await cred.user!.updateDisplayName(name.trim());
    await cred.user!.reload();
    user = _auth.currentUser;
    try {
      await _createIdentity(password);
    } catch (_) {
      // Account exists but keys weren't published; unlocking will retry.
      _lock();
      rethrow;
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    final cred = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    user = cred.user;
    try {
      await _restoreIdentity(currentPassword: password);
    } on WrongPasswordException {
      backupPasswordMismatch = true;
      _lock();
    } catch (_) {
      _lock();
      rethrow;
    }
  }

  /// From the lock screen. [previousPassword] is for backups wrapped with a
  /// password that has since been reset.
  Future<void> unlock({required String password, String? previousPassword}) async {
    await _reauthenticate(password);
    try {
      await _restoreIdentity(currentPassword: password, backupPassword: previousPassword);
    } on WrongPasswordException {
      backupPasswordMismatch = true;
      notifyListeners();
      rethrow;
    }
  }

  /// Replaces the key pair. Packages encrypted for the old key become
  /// permanently unreadable, which is the point if a key is compromised.
  Future<void> resetKeys(String password) async {
    await _reauthenticate(password);
    await _createIdentity(password);
  }

  Future<void> changePassword({required String current, required String next}) async {
    await _reauthenticate(current);
    final id = identity!;
    await _busy('Re-encrypting your key backup…', () async {
      final backup = await compute(wrapPrivateKey, WrapRequest(id.privateDer, next));
      await user!.updatePassword(next);
      await directory.updateVault(user!.uid, backup);
    });
  }

  Future<void> sendPasswordReset(String email) => _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> updateDisplayName(String name) async {
    await user!.updateDisplayName(name.trim());
    await directory.updateDisplayName(user!.uid, name.trim());
    await user!.reload();
    user = _auth.currentUser;
    notifyListeners();
  }

  Future<void> signOut() async {
    // Remove the decrypted key from this device; the encrypted backup stays.
    final uid = user?.uid;
    if (uid != null) await _keys.clear(uid);
    await _auth.signOut();
    _reset();
  }

  Future<void> _createIdentity(String password) async {
    final u = user!;
    await _busy('Generating your 2048-bit RSA key pair…', () async {
      final id = await generateIdentityFast();
      busyMessage = 'Encrypting your private key backup…';
      notifyListeners();
      final backup = await compute(wrapPrivateKey, WrapRequest(id.privateDer, password));
      await directory.publishIdentity(
        uid: u.uid,
        email: u.email!,
        displayName: u.displayName ?? '',
        identity: id,
        backup: backup,
      );
      await _keys.save(u.uid, id);
      identity = id;
    });
    _ready(identity!);
  }

  Future<void> _restoreIdentity({required String currentPassword, String? backupPassword}) async {
    final uid = user!.uid;
    final local = await _keys.load(uid);
    if (local != null && await _matchesDirectory(uid, local)) return _ready(local);

    final backup = await directory.fetchVault(uid);
    if (backup == null) return _createIdentity(currentPassword); // first sign-in

    late RsaIdentity id;
    await _busy('Unlocking your private key…', () async {
      final der = await compute(unwrapPrivateKey, UnwrapRequest(backup, backupPassword ?? currentPassword));
      id = identityFromPrivate(der);
      if (backupPassword != null) {
        // Re-wrap under the current password so this is a one-time step.
        await directory.updateVault(uid, await compute(wrapPrivateKey, WrapRequest(der, currentPassword)));
      }
      await _keys.save(uid, id);
    });
    _ready(id);
  }

  /// True if [local] is still the key published in the directory (it won't be
  /// if the keys were reset from another device). Offline: trust local.
  Future<bool> _matchesDirectory(String uid, RsaIdentity local) async {
    try {
      final published = await directory.fetchPublicKey(uid);
      if (published == null) return false;
      if (!const ListEquality<int>().equals(published, local.publicDer)) {
        await _keys.clear(uid);
        return false;
      }
      return true;
    } on FirebaseException catch (e) {
      return e.code == 'unavailable';
    }
  }

  Future<void> _reauthenticate(String password) => user!.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: user!.email!, password: password),
      );

  Future<void> _busy(String message, Future<void> Function() task) async {
    busyMessage = message;
    notifyListeners();
    // Let the progress UI paint first; on web `compute` runs on this thread.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    try {
      await task();
    } finally {
      busyMessage = null;
      notifyListeners();
    }
  }

  void _ready(RsaIdentity id) {
    identity = id;
    backupPasswordMismatch = false;
    status = SessionStatus.ready;
    notifyListeners();
  }

  void _lock() {
    identity = null;
    status = SessionStatus.locked;
    notifyListeners();
  }

  void _reset() {
    user = null;
    identity = null;
    backupPasswordMismatch = false;
    busyMessage = null;
    status = SessionStatus.signedOut;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

/// Human-readable message for errors surfaced in the UI.
String describeError(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'weak-password':
        return 'Password is too weak; use at least 8 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection.';
      case 'operation-not-allowed':
      case 'configuration-not-found':
        return 'Email/password sign-in is not enabled in the Firebase console.';
      case 'requires-recent-login':
        return 'Please sign in again to do this.';
    }
    return error.message ?? error.code;
  }
  if (error is FirebaseException) {
    if (error.code == 'permission-denied') {
      return 'Permission denied by Firestore rules.';
    }
    if (error.code == 'unavailable') return 'Server unavailable. Check your connection.';
    return error.message ?? error.code;
  }
  return error.toString().replaceFirst('Exception: ', '');
}
