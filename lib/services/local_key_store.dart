import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/rsa_keys.dart';

/// Keeps the unlocked private key in the platform keystore (Keychain /
/// Android Keystore-backed storage / WebCrypto-wrapped storage on web).
class LocalKeyStore {
  static const _storage = FlutterSecureStorage(
    // The legacy file keychain works for unsigned macOS debug builds.
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  static String _pub(String uid) => 'pub_$uid';
  static String _priv(String uid) => 'priv_$uid';

  Future<RsaIdentity?> load(String uid) async {
    try {
      final pub = await _storage.read(key: _pub(uid));
      final priv = await _storage.read(key: _priv(uid));
      if (pub == null || priv == null) return null;
      return RsaIdentity(publicDer: base64.decode(pub), privateDer: base64.decode(priv));
    } catch (_) {
      // Corrupt or inaccessible entry: treat as missing and restore from backup.
      return null;
    }
  }

  Future<void> save(String uid, RsaIdentity identity) async {
    await _storage.write(key: _pub(uid), value: base64.encode(identity.publicDer));
    await _storage.write(key: _priv(uid), value: base64.encode(identity.privateDer));
  }

  Future<void> clear(String uid) async {
    await _storage.delete(key: _pub(uid));
    await _storage.delete(key: _priv(uid));
  }
}
